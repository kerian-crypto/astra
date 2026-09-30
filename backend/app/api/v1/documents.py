import uuid
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, File, Form, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import AppSettings, CurrentUser, DbSession, Storage, UploadQuota
from app.core.config import Settings
from app.core.storage import LocalFileStorage
from app.models import User
from app.models.enums import DocumentKind, ProjectRole
from app.schemas.document import DocumentPublic
from app.services import document_service, project_service

router = APIRouter(tags=["documents"])


Title = Annotated[str, Form(min_length=1, max_length=200)]
Kind = Annotated[DocumentKind, Form()]
Upload = Annotated[UploadFile, File()]


def _upload(
    db: Session,
    storage: LocalFileStorage,
    settings: Settings,
    user: User,
    project_id: uuid.UUID | None,
    title: str,
    kind: DocumentKind,
    file: UploadFile,
) -> DocumentPublic:
    document = document_service.upload(
        db,
        storage,
        user,
        project_id=project_id,
        title=title,
        kind=kind,
        filename=file.filename or "document",
        source=file.file,
        max_bytes=settings.MAX_UPLOAD_BYTES,
    )
    return document_service.to_public(document)


@router.get("/documents", response_model=list[DocumentPublic])
def list_general_documents(
    user: CurrentUser,
    db: DbSession,
    kind: DocumentKind | None = None,
    all_visible: Annotated[bool, Query(description="inclure ceux des projets")] = False,
) -> list[DocumentPublic]:
    documents = document_service.list_documents(
        db, user, project_id=None, general_only=not all_visible, kind=kind
    )
    return [document_service.to_public(d) for d in documents]


@router.post(
    "/documents",
    response_model=DocumentPublic,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def upload_general_document(
    title: Title,
    kind: Kind,
    file: Upload,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
) -> DocumentPublic:
    return _upload(db, storage, settings, user, None, title, kind, file)


@router.get("/projects/{project_id}/documents", response_model=list[DocumentPublic])
def list_project_documents(
    project_id: uuid.UUID, user: CurrentUser, db: DbSession, kind: DocumentKind | None = None
) -> list[DocumentPublic]:
    project_service.get_accessible_project(db, user, project_id, ProjectRole.VIEWER)
    documents = document_service.list_documents(db, user, project_id=project_id, kind=kind)
    return [document_service.to_public(d) for d in documents]


@router.post(
    "/projects/{project_id}/documents",
    response_model=DocumentPublic,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def upload_project_document(
    project_id: uuid.UUID,
    title: Title,
    kind: Kind,
    file: Upload,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
) -> DocumentPublic:
    return _upload(db, storage, settings, user, project_id, title, kind, file)


@router.get("/documents/{document_id}", response_model=DocumentPublic)
def read_document(document_id: uuid.UUID, user: CurrentUser, db: DbSession) -> DocumentPublic:
    return document_service.to_public(
        document_service.get_accessible_document(db, user, document_id)
    )


@router.get("/documents/{document_id}/download", response_class=FileResponse)
def download_document(
    document_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    document = document_service.get_accessible_document(db, user, document_id)
    return FileResponse(
        storage.path(document.storage_key),
        media_type=document.content_type,
        headers={
            # Toujours en pièce jointe : le navigateur n'interprète pas le contenu.
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(document.filename)}",
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, no-store",
        },
    )


@router.delete("/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document(
    document_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> None:
    document = document_service.get_accessible_document(db, user, document_id)
    document_service.delete(db, storage, user, document)
