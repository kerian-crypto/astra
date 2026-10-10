"""Espace documentaire du client (§21-23) : agrège les documents de projet
partagés, les fichiers des livrables publiés, des contrats et des factures.
Chaque source applique sa propre règle d'accès."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    ClientAccount,
    Contract,
    Deliverable,
    DeliverableVersion,
    Document,
    Invoice,
    Project,
    User,
)
from app.models.client_enums import (
    ClientNotificationKind,
    ClientPermission,
    ContractStatus,
    DeliverableStatus,
    DocumentVisibility,
    InvoiceStatus,
)
from app.models.enums import DocumentKind
from app.schemas.client.document import ClientDocumentView, DocumentCategory, DocumentSource
from app.services import activity_service
from app.services.client import access, audit, notifications
from app.services.errors import ConflictError, NotFoundError

DOCUMENT_NOT_FOUND = "Document introuvable."

_CATEGORY_BY_KIND = {
    DocumentKind.SPECIFICATION: DocumentCategory.SPECIFICATION,
    DocumentKind.CONTRACT: DocumentCategory.CONTRACT,
    DocumentKind.DELIVERABLE: DocumentCategory.DELIVERABLE,
    DocumentKind.MINUTES: DocumentCategory.REPORT,
    DocumentKind.LESSONS: DocumentCategory.REPORT,
    DocumentKind.GUIDE: DocumentCategory.ADMINISTRATIVE,
}


def _project_names(db: Session, account: ClientAccount) -> dict[uuid.UUID, str]:
    return dict(
        db.execute(
            select(Project.id, Project.name).where(Project.client_company_id == account.company_id)
        ).all()
    )


def shared_documents_statement(account: ClientAccount):
    """Dernière version de chaque document partagé des projets de l'entreprise."""
    latest = (
        select(Document.version_group_id, func.max(Document.version).label("version"))
        .where(
            Document.project_id.in_(access.company_project_ids(account)),
            Document.visibility == DocumentVisibility.CLIENT,
        )
        .group_by(Document.version_group_id)
        .subquery()
    )
    return (
        select(Document)
        .join(
            latest,
            (Document.version_group_id == latest.c.version_group_id)
            & (Document.version == latest.c.version),
        )
        .where(
            Document.project_id.in_(access.company_project_ids(account)),
            Document.visibility == DocumentVisibility.CLIENT,
        )
    )


def _from_document(document: Document, names: dict[uuid.UUID, str]) -> ClientDocumentView:
    return ClientDocumentView(
        id=document.id,
        source=DocumentSource.DOCUMENT,
        category=_CATEGORY_BY_KIND.get(document.kind, DocumentCategory.OTHER),
        title=document.title,
        filename=document.filename,
        content_type=document.content_type,
        size_bytes=document.size_bytes,
        version=document.version,
        project_id=document.project_id,
        project_name=names.get(document.project_id) if document.project_id else None,
        created_at=document.created_at,
        download_path=f"client/documents/{document.id}/download",
    )


def list_documents(
    db: Session,
    account: ClientAccount,
    *,
    category: DocumentCategory | None = None,
    project_id: uuid.UUID | None = None,
    limit: int = 200,
) -> list[ClientDocumentView]:
    access.require(account, ClientPermission.VIEW_DOCUMENT)
    names = _project_names(db, account)
    views: list[ClientDocumentView] = []

    shared = shared_documents_statement(account)
    if project_id is not None:
        shared = shared.where(Document.project_id == project_id)
    views += [_from_document(d, names) for d in db.scalars(shared)]

    if account.has_permission(ClientPermission.VIEW_PROJECT):
        versions = db.execute(
            select(DeliverableVersion, Deliverable)
            .join(Deliverable, Deliverable.id == DeliverableVersion.deliverable_id)
            .where(
                Deliverable.project_id.in_(access.company_project_ids(account)),
                Deliverable.status != DeliverableStatus.DRAFT,
                DeliverableVersion.file_key.is_not(None),
            )
        ).all()
        views += [
            ClientDocumentView(
                id=version.id,
                source=DocumentSource.DELIVERABLE,
                category=DocumentCategory.DELIVERABLE,
                title=deliverable.title,
                filename=version.file_name or "livrable",
                content_type=version.file_content_type or "application/octet-stream",
                size_bytes=version.file_size or 0,
                version=version.number,
                project_id=deliverable.project_id,
                project_name=names.get(deliverable.project_id),
                created_at=version.created_at,
                download_path=f"client/deliverables/{deliverable.id}/versions/{version.id}/download",
            )
            for version, deliverable in versions
            if project_id in (None, deliverable.project_id)
        ]

    if account.has_permission(ClientPermission.VIEW_CONTRACT):
        contracts = db.scalars(
            select(Contract).where(
                Contract.company_id == account.company_id,
                Contract.status != ContractStatus.DRAFT,
                Contract.file_key.is_not(None),
            )
        )
        views += [
            _attached(c, DocumentSource.CONTRACT, DocumentCategory.CONTRACT, names, "contracts")
            for c in contracts
            if project_id in (None, c.project_id)
        ]

    if account.has_permission(ClientPermission.VIEW_INVOICE):
        invoices = db.scalars(
            select(Invoice).where(
                Invoice.company_id == account.company_id,
                Invoice.status != InvoiceStatus.CANCELLED,
                Invoice.file_key.is_not(None),
            )
        )
        views += [
            _attached(i, DocumentSource.INVOICE, DocumentCategory.INVOICE, names, "invoices")
            for i in invoices
            if project_id in (None, i.project_id)
        ]

    if category is not None:
        views = [v for v in views if v.category == category]
    views.sort(key=lambda v: v.created_at, reverse=True)
    return views[:limit]


def _attached(
    entity: Contract | Invoice,
    source: DocumentSource,
    category: DocumentCategory,
    names: dict[uuid.UUID, str],
    route: str,
) -> ClientDocumentView:
    title = f"{entity.number} — {entity.title}"
    return ClientDocumentView(
        id=entity.id,
        source=source,
        category=category,
        title=title,
        filename=entity.file_name or "document",
        content_type=entity.file_content_type or "application/octet-stream",
        size_bytes=entity.file_size or 0,
        version=1,
        project_id=entity.project_id,
        project_name=names.get(entity.project_id) if entity.project_id else None,
        created_at=entity.created_at,
        download_path=f"client/{route}/{entity.id}/download",
    )


def get_shared_document(db: Session, account: ClientAccount, document_id: uuid.UUID) -> Document:
    """Toute version d'un document partagé (pas seulement la dernière)."""
    access.require(account, ClientPermission.VIEW_DOCUMENT)
    document = db.scalar(
        select(Document).where(
            Document.id == document_id,
            Document.project_id.in_(access.company_project_ids(account)),
            Document.visibility == DocumentVisibility.CLIENT,
        )
    )
    if document is None:
        raise NotFoundError(DOCUMENT_NOT_FOUND)
    return document


def versions(db: Session, account: ClientAccount, document: Document) -> list[ClientDocumentView]:
    names = _project_names(db, account)
    rows = db.scalars(
        select(Document)
        .where(
            Document.version_group_id == document.version_group_id,
            Document.project_id == document.project_id,
            Document.visibility == DocumentVisibility.CLIENT,
        )
        .order_by(Document.version.desc())
    )
    return [_from_document(d, names) for d in rows]


def record_download(
    db: Session,
    account: ClientAccount,
    *,
    entity_type: str,
    entity_id: uuid.UUID,
    title: str,
    project_id: uuid.UUID | None,
) -> None:
    access.require(account, ClientPermission.DOWNLOAD_DOCUMENT)
    audit.record(
        db,
        account,
        project_id=project_id,
        entity_type=entity_type,
        entity_id=entity_id,
        action="downloaded",
        changes={"title": title},
    )
    db.commit()


# ---------- Astra Hub : partage et versions ----------


def set_visibility(
    db: Session, user: User, document: Document, visibility: DocumentVisibility
) -> Document:
    """Partage (ou retire) un document de projet avec le client (§22)."""
    if document.project_id is None:
        raise ConflictError("Seuls les documents d'un projet peuvent être partagés avec un client.")
    project = db.get(Project, document.project_id)
    if visibility == DocumentVisibility.CLIENT and project.client_company_id is None:
        raise ConflictError("Rattachez d'abord le projet à une entreprise cliente.")
    if document.visibility == visibility:
        return document
    document.visibility = visibility
    activity_service.record(
        db,
        actor=user,
        project_id=project.id,
        entity_type="document",
        entity_id=document.id,
        action="shared_with_client" if visibility == DocumentVisibility.CLIENT else "unshared",
        changes={"title": document.title},
    )
    if visibility == DocumentVisibility.CLIENT:
        notify_document_available(db, project, document)
    db.commit()
    return document


def notify_document_available(db: Session, project: Project, document: Document) -> None:
    notifications.notify_company(
        db,
        project.client_company_id,
        ClientPermission.VIEW_DOCUMENT,
        kind=ClientNotificationKind.DOCUMENT_AVAILABLE,
        title=f"Nouveau document : {document.title}",
        body=project.name
        if document.version == 1
        else f"{project.name} · version {document.version}",
        entity_type="document",
        entity_id=document.id,
    )
