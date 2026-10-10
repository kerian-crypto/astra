"""Livrables : préparés et publiés dans Astra Hub, consultés et validés dans
Astra Client (§18-20, §61-62)."""

import uuid
from typing import BinaryIO
from urllib.parse import urlparse

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.storage import LocalFileStorage
from app.models import (
    ClientAccount,
    Deliverable,
    DeliverableReview,
    DeliverableVersion,
    Project,
    User,
)
from app.models.client_enums import (
    ClientNotificationKind,
    ClientPermission,
    DeliverableStatus,
    ReviewAction,
)
from app.models.enums import NotificationKind, ProjectRole
from app.schemas.client.common import attached_file
from app.schemas.client.deliverable import (
    DeliverableCreate,
    DeliverableDetailView,
    DeliverableHub,
    DeliverableUpdate,
    DeliverableView,
    ReviewView,
    VersionHub,
    VersionView,
)
from app.services import activity_service, notification_service
from app.services.client import access, audit, files, notifications
from app.services.errors import ConflictError, NotFoundError, ServiceError

MAX_NOTES_LENGTH = 5_000
MAX_LINK_LENGTH = 500
REVIEWABLE = frozenset({DeliverableStatus.AWAITING_VALIDATION})


# ---------- Représentations ----------


def _version_view(version: DeliverableVersion) -> VersionView:
    return VersionView(
        id=version.id,
        number=version.number,
        notes=version.notes,
        link_url=version.link_url,
        file=attached_file(version),
        published_at=version.created_at,
    )


def _review_view(review: DeliverableReview) -> ReviewView:
    return ReviewView(
        id=review.id,
        version_number=review.version_number,
        action=review.action,
        reviewer_name=review.reviewer_name,
        reason=review.reason,
        comment=review.comment,
        file=attached_file(review),
        created_at=review.created_at,
    )


def _reviews(db: Session, deliverable: Deliverable) -> list[DeliverableReview]:
    return list(
        db.scalars(
            select(DeliverableReview)
            .where(DeliverableReview.deliverable_id == deliverable.id)
            .order_by(DeliverableReview.created_at.desc())
        )
    )


def get_review(db: Session, deliverable: Deliverable, review_id: uuid.UUID) -> DeliverableReview:
    review = db.get(DeliverableReview, review_id)
    if review is None or review.deliverable_id != deliverable.id:
        raise NotFoundError("Validation introuvable.")
    return review


def to_view(db: Session, deliverable: Deliverable) -> DeliverableView:
    project = db.get(Project, deliverable.project_id)
    current = deliverable.current_version
    return DeliverableView(
        id=deliverable.id,
        project_id=deliverable.project_id,
        project_name=project.name if project else "",
        title=deliverable.title,
        description=deliverable.description,
        status=deliverable.status,
        requires_validation=deliverable.requires_validation,
        due_date=deliverable.due_date,
        current_version=_version_view(current) if current else None,
        updated_at=deliverable.updated_at,
    )


def to_detail_view(
    db: Session, account: ClientAccount, deliverable: Deliverable
) -> DeliverableDetailView:
    return DeliverableDetailView(
        **to_view(db, deliverable).model_dump(),
        versions=[_version_view(v) for v in deliverable.versions],
        reviews=[_review_view(r) for r in _reviews(db, deliverable)],
        can_review=deliverable.status in REVIEWABLE
        and account.has_permission(ClientPermission.VALIDATE_DELIVERABLE),
    )


def to_hub(db: Session, deliverable: Deliverable) -> DeliverableHub:
    return DeliverableHub(
        **to_view(db, deliverable).model_dump(),
        created_at=deliverable.created_at,
        versions=[
            VersionHub(
                **_version_view(v).model_dump(),
                published_by_name=v.published_by.full_name if v.published_by else None,
            )
            for v in deliverable.versions
        ],
        reviews=[_review_view(r) for r in _reviews(db, deliverable)],
    )


# ---------- Astra Hub ----------


def list_for_project(db: Session, project: Project) -> list[Deliverable]:
    return list(
        db.scalars(
            select(Deliverable)
            .where(Deliverable.project_id == project.id)
            .order_by(Deliverable.created_at.desc())
        )
    )


def get_for_hub(db: Session, deliverable_id: uuid.UUID) -> Deliverable:
    deliverable = db.get(Deliverable, deliverable_id)
    if deliverable is None:
        raise NotFoundError(access.DELIVERABLE_NOT_FOUND)
    return deliverable


def create(db: Session, user: User, project: Project, data: DeliverableCreate) -> Deliverable:
    deliverable = Deliverable(project_id=project.id, created_by_id=user.id, **data.model_dump())
    db.add(deliverable)
    db.flush()
    activity_service.record(
        db,
        actor=user,
        project_id=project.id,
        entity_type="deliverable",
        entity_id=deliverable.id,
        action="created",
        changes={"title": deliverable.title},
    )
    db.commit()
    return deliverable


def update(
    db: Session, user: User, deliverable: Deliverable, data: DeliverableUpdate
) -> Deliverable:
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(deliverable, changes)
    for field, value in changes.items():
        setattr(deliverable, field, value)
    if delta:
        activity_service.record(
            db,
            actor=user,
            project_id=deliverable.project_id,
            entity_type="deliverable",
            entity_id=deliverable.id,
            action="updated",
            changes=delta,
        )
    db.commit()
    return deliverable


def _clean_link(link_url: str | None) -> str | None:
    if not link_url or not link_url.strip():
        return None
    link = link_url.strip()
    parsed = urlparse(link)
    # Uniquement https : le lien est ouvert sur le téléphone du client.
    if parsed.scheme != "https" or not parsed.netloc or len(link) > MAX_LINK_LENGTH:
        raise ServiceError("Le lien doit être une adresse https valide.")
    return link


def publish_version(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    deliverable: Deliverable,
    project: Project,
    *,
    notes: str | None,
    link_url: str | None,
    upload: tuple[str, BinaryIO] | None,
    max_bytes: int,
) -> Deliverable:
    """Publie une nouvelle version au client (§61). Le livrable passe en
    attente de validation si elle est requise."""
    if project.client_company_id is None:
        raise ConflictError("Rattachez d'abord le projet à une entreprise cliente.")
    link = _clean_link(link_url)
    if upload is None and link is None:
        raise ServiceError("Ajoutez un fichier ou un lien.")
    if notes is not None and len(notes) > MAX_NOTES_LENGTH:
        raise ServiceError("Notes trop longues.")

    number = (deliverable.current_version.number if deliverable.current_version else 0) + 1
    version = DeliverableVersion(
        deliverable_id=deliverable.id,
        number=number,
        notes=(notes or "").strip() or None,
        link_url=link,
        published_by_id=user.id,
    )
    stored_key = None
    if upload is not None:
        filename, source = upload
        stored_key = files.attach(
            storage, version, filename=filename, source=source, max_bytes=max_bytes
        )
    try:
        db.add(version)
        deliverable.status = (
            DeliverableStatus.AWAITING_VALIDATION
            if deliverable.requires_validation
            else DeliverableStatus.PUBLISHED
        )
        db.flush()
        activity_service.record(
            db,
            actor=user,
            project_id=project.id,
            entity_type="deliverable",
            entity_id=deliverable.id,
            action="version_published",
            changes={"title": deliverable.title, "version": number},
        )
        kind = (
            ClientNotificationKind.VALIDATION_REQUIRED
            if deliverable.requires_validation
            else ClientNotificationKind.DELIVERABLE_READY
        )
        title = (
            f"Validation requise : {deliverable.title}"
            if deliverable.requires_validation
            else f"Nouveau livrable : {deliverable.title}"
        )
        notifications.notify_company(
            db,
            project.client_company_id,
            ClientPermission.VIEW_PROJECT,
            kind=kind,
            title=title,
            body=f"{project.name} · version {number}",
            entity_type="deliverable",
            entity_id=deliverable.id,
        )
        db.commit()
    except Exception:
        db.rollback()
        if stored_key:
            storage.delete(stored_key)
        raise
    db.refresh(deliverable)
    return deliverable


# ---------- Astra Client ----------


def list_for_client(
    db: Session, account: ClientAccount, *, project_id: uuid.UUID | None, pending_only: bool
) -> list[Deliverable]:
    access.require(account, ClientPermission.VIEW_PROJECT)
    statement = access.visible_deliverables_statement(account)
    if project_id is not None:
        statement = statement.where(Deliverable.project_id == project_id)
    if pending_only:
        statement = statement.where(Deliverable.status == DeliverableStatus.AWAITING_VALIDATION)
    return list(db.scalars(statement.order_by(Deliverable.updated_at.desc())))


def get_version_for_client(
    db: Session, account: ClientAccount, deliverable_id: uuid.UUID, version_id: uuid.UUID
) -> DeliverableVersion:
    deliverable = access.get_deliverable(db, account, deliverable_id)
    access.require(account, ClientPermission.DOWNLOAD_DOCUMENT)
    version = next((v for v in deliverable.versions if v.id == version_id), None)
    if version is None or not version.file_key:
        raise NotFoundError("Version introuvable.")
    audit.record(
        db,
        account,
        project_id=deliverable.project_id,
        entity_type="deliverable",
        entity_id=deliverable.id,
        action="downloaded",
        changes={"title": deliverable.title, "version": version.number},
    )
    db.commit()
    return version


def review(
    db: Session,
    storage: LocalFileStorage,
    account: ClientAccount,
    deliverable: Deliverable,
    *,
    action: ReviewAction,
    reason: str | None,
    comment: str | None,
    upload: tuple[str, BinaryIO] | None,
    max_bytes: int,
) -> Deliverable:
    """Approbation ou demande de modification de la version courante (§19).
    Chaque décision est conservée (§20) et arrive immédiatement dans Astra Hub."""
    access.require(account, ClientPermission.VALIDATE_DELIVERABLE)
    # Verrou : deux collègues ne valident pas la même version en même temps.
    db.execute(select(Deliverable.id).where(Deliverable.id == deliverable.id).with_for_update())
    db.refresh(deliverable)
    if deliverable.status not in REVIEWABLE or deliverable.current_version is None:
        raise ConflictError("Ce livrable n'attend pas de validation.")
    reason = (reason or "").strip() or None
    comment = (comment or "").strip() or None
    if action == ReviewAction.REQUEST_CHANGES and not (reason or comment):
        raise ServiceError("Précisez le motif de la modification demandée.")

    version = deliverable.current_version
    entry = DeliverableReview(
        deliverable_id=deliverable.id,
        version_id=version.id,
        account_id=account.id,
        company_id=account.company_id,
        reviewer_name=account.full_name,
        version_number=version.number,
        action=action,
        reason=reason,
        comment=comment,
    )
    stored_key = None
    if upload is not None:
        filename, source = upload
        stored_key = files.attach(
            storage, entry, filename=filename, source=source, max_bytes=max_bytes, allow_media=True
        )
    try:
        db.add(entry)
        approved = action == ReviewAction.APPROVE
        deliverable.status = (
            DeliverableStatus.APPROVED if approved else DeliverableStatus.CHANGES_REQUESTED
        )
        audit.record(
            db,
            account,
            project_id=deliverable.project_id,
            entity_type="deliverable",
            entity_id=deliverable.id,
            action="approved" if approved else "changes_requested",
            changes={"title": deliverable.title, "version": version.number, "reason": reason},
        )
        _notify_hub_of_review(db, account, deliverable, approved)
        db.commit()
    except Exception:
        db.rollback()
        if stored_key:
            storage.delete(stored_key)
        raise
    return deliverable


def _notify_hub_of_review(
    db: Session, account: ClientAccount, deliverable: Deliverable, approved: bool
) -> None:
    project = db.get(Project, deliverable.project_id)
    leads = [m.user_id for m in project.memberships if m.role == ProjectRole.LEAD]
    recipients = [*leads, deliverable.created_by_id] if deliverable.created_by_id else leads
    verdict = "a approuvé" if approved else "demande une modification de"
    notification_service.notify_many(
        db,
        user_ids=recipients,
        actor=None,
        kind=NotificationKind.CLIENT_REVIEW,
        title=f"{account.company.name} {verdict} « {deliverable.title} »",
        body=f"{account.full_name} · {project.name}",
        entity_type="deliverable",
        entity_id=deliverable.id,
    )
