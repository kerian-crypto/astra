import uuid
from typing import BinaryIO

from sqlalchemy import Select, or_, select
from sqlalchemy.orm import Session

from app.core.storage import FileTooLargeError, LocalFileStorage
from app.models import Document, Project, User
from app.models.enums import DocumentKind, NotificationKind, ProjectRole
from app.schemas.document import DocumentPublic
from app.services import (
    activity_service,
    file_types,
    notification_service,
    permissions,
    project_service,
)
from app.services.errors import NotFoundError, PermissionDeniedError, ServiceError

DOCUMENT_NOT_FOUND = "Document introuvable."
MAX_FILENAME_LENGTH = 255


def visible_documents_statement(user: User) -> Select[tuple[Document]]:
    """Documents généraux d'Astra + documents des projets visibles."""
    return select(Document).where(
        or_(
            Document.project_id.is_(None),
            Document.project_id.in_(permissions.visible_project_ids(user)),
        )
    )


def to_public(document: Document) -> DocumentPublic:
    public = DocumentPublic.model_validate(document)
    public.is_indexed = document.text_content is not None
    return public


def list_documents(
    db: Session,
    user: User,
    *,
    project_id: uuid.UUID | None,
    general_only: bool = False,
    kind: DocumentKind | None = None,
) -> list[Document]:
    statement = visible_documents_statement(user)
    if general_only:
        statement = statement.where(Document.project_id.is_(None))
    elif project_id is not None:
        statement = statement.where(Document.project_id == project_id)
    if kind is not None:
        statement = statement.where(Document.kind == kind)
    return list(db.scalars(statement.order_by(Document.created_at.desc())))


def get_accessible_document(db: Session, user: User, document_id: uuid.UUID) -> Document:
    document = db.scalar(visible_documents_statement(user).where(Document.id == document_id))
    if document is None:
        raise NotFoundError(DOCUMENT_NOT_FOUND)
    return document


def _check_can_upload(db: Session, user: User, project_id: uuid.UUID | None) -> Project | None:
    if project_id is None:
        if not permissions.can_create_project(user):
            raise PermissionDeniedError(
                "Seuls les managers et administrateurs publient des documents généraux."
            )
        return None
    project, _ = project_service.get_accessible_project(
        db, user, project_id, ProjectRole.CONTRIBUTOR
    )
    return project


def _safe_filename(filename: str) -> str:
    """Nom affiché et proposé au téléchargement : sans chemin ni caractères de contrôle."""
    name = filename.replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(ch for ch in name if ch.isprintable() and ch not in '"<>|:*?')
    return name.strip()[:MAX_FILENAME_LENGTH] or "document"


def upload(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    *,
    project_id: uuid.UUID | None,
    title: str,
    kind: DocumentKind,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> Document:
    project = _check_can_upload(db, user, project_id)
    file_type = file_types.resolve(filename)
    if file_type is None:
        allowed = ", ".join(sorted(file_types.FILE_TYPES))
        raise ServiceError(f"Format non accepté. Formats possibles : {allowed}.")

    try:
        stored = storage.save(source, max_bytes)
    except FileTooLargeError:
        raise ServiceError(
            f"Fichier trop volumineux (max {max_bytes // (1024 * 1024)} Mo)."
        ) from None
    if stored.size_bytes == 0 or not file_types.matches_signature(file_type, stored.head):
        storage.delete(stored.key)
        raise ServiceError("Le contenu du fichier ne correspond pas à son extension.")

    document = Document(
        project_id=project_id,
        title=title.strip(),
        kind=kind,
        filename=_safe_filename(filename),
        content_type=file_type.content_type,
        size_bytes=stored.size_bytes,
        sha256=stored.sha256,
        storage_key=stored.key,
        text_content=file_types.extract_text(file_type, storage.path(stored.key)),
        uploaded_by_id=user.id,
    )
    db.add(document)
    try:
        db.flush()
        activity_service.record(
            db,
            actor=user,
            project_id=project_id,
            entity_type="document",
            entity_id=document.id,
            action="uploaded",
            changes={"title": document.title},
        )
        if project is not None:
            notification_service.notify_many(
                db,
                user_ids=project_service.member_ids(project),
                actor=user,
                kind=NotificationKind.DOCUMENT_ADDED,
                title=f"Nouveau document dans « {project.name} »",
                body=f"{document.title} · ajouté par {user.full_name}",
                entity_type="project",
                entity_id=project.id,
            )
        db.commit()
    except Exception:
        db.rollback()
        storage.delete(stored.key)
        raise
    return document


def delete(db: Session, storage: LocalFileStorage, user: User, document: Document) -> None:
    """Auteur de l'envoi, responsable du projet ou administrateur."""
    is_uploader = document.uploaded_by_id == user.id
    if document.project_id is None:
        allowed = is_uploader or permissions.is_admin(user)
    else:
        project = db.get(Project, document.project_id)
        allowed = is_uploader or (
            permissions.get_project_role(db, user, project) == ProjectRole.LEAD
        )
    if not allowed:
        raise PermissionDeniedError("Vous ne pouvez pas supprimer ce document.")
    activity_service.record(
        db,
        actor=user,
        project_id=document.project_id,
        entity_type="document",
        entity_id=document.id,
        action="deleted",
        changes={"title": document.title},
    )
    key = document.storage_key
    db.delete(document)
    db.commit()
    storage.delete(key)
