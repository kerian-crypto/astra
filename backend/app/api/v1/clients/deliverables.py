"""Livrables (côté Hub) et partage des documents avec le client."""

import uuid
from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict

from app.api.deps import AppSettings, CurrentUser, DbSession, Storage, UploadQuota
from app.api.files import attached_file_response
from app.models.client_enums import DocumentVisibility
from app.models.enums import ProjectRole
from app.schemas.client.deliverable import DeliverableCreate, DeliverableHub, DeliverableUpdate
from app.schemas.document import DocumentPublic
from app.services import document_service, project_service
from app.services.client import deliverables
from app.services.client import documents as client_documents
from app.services.errors import NotFoundError

router = APIRouter(tags=["clients"])


class VisibilityUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    visibility: DocumentVisibility


def _load(db, user, deliverable_id: uuid.UUID, minimum: ProjectRole):
    deliverable = deliverables.get_for_hub(db, deliverable_id)
    project, _ = project_service.get_accessible_project(db, user, deliverable.project_id, minimum)
    return deliverable, project


@router.get("/projects/{project_id}/deliverables", response_model=list[DeliverableHub])
def list_deliverables(
    project_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> list[DeliverableHub]:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.VIEWER)
    return [deliverables.to_hub(db, d) for d in deliverables.list_for_project(db, project)]


@router.post(
    "/projects/{project_id}/deliverables",
    response_model=DeliverableHub,
    status_code=status.HTTP_201_CREATED,
)
def create_deliverable(
    project_id: uuid.UUID, body: DeliverableCreate, user: CurrentUser, db: DbSession
) -> DeliverableHub:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.LEAD)
    return deliverables.to_hub(db, deliverables.create(db, user, project, body))


@router.get("/deliverables/{deliverable_id}", response_model=DeliverableHub)
def read_deliverable(deliverable_id: uuid.UUID, user: CurrentUser, db: DbSession) -> DeliverableHub:
    deliverable, _ = _load(db, user, deliverable_id, ProjectRole.VIEWER)
    return deliverables.to_hub(db, deliverable)


@router.patch("/deliverables/{deliverable_id}", response_model=DeliverableHub)
def update_deliverable(
    deliverable_id: uuid.UUID, body: DeliverableUpdate, user: CurrentUser, db: DbSession
) -> DeliverableHub:
    deliverable, _ = _load(db, user, deliverable_id, ProjectRole.LEAD)
    return deliverables.to_hub(db, deliverables.update(db, user, deliverable, body))


@router.post(
    "/deliverables/{deliverable_id}/versions",
    response_model=DeliverableHub,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def publish_version(
    deliverable_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    notes: Annotated[str | None, Form(max_length=5_000)] = None,
    link_url: Annotated[str | None, Form(max_length=500)] = None,
    file: Annotated[UploadFile | None, File()] = None,
) -> DeliverableHub:
    """Publie une nouvelle version au client (fichier et/ou lien https)."""
    deliverable, project = _load(db, user, deliverable_id, ProjectRole.LEAD)
    deliverables.publish_version(
        db,
        storage,
        user,
        deliverable,
        project,
        notes=notes,
        link_url=link_url,
        upload=(file.filename or "livrable", file.file) if file else None,
        max_bytes=settings.MAX_UPLOAD_BYTES,
    )
    return deliverables.to_hub(db, deliverable)


@router.get(
    "/deliverables/{deliverable_id}/versions/{version_id}/download", response_class=FileResponse
)
def download_version(
    deliverable_id: uuid.UUID,
    version_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    deliverable, _ = _load(db, user, deliverable_id, ProjectRole.VIEWER)
    version = next((v for v in deliverable.versions if v.id == version_id), None)
    if version is None:
        raise NotFoundError("Version introuvable.")
    return attached_file_response(storage, version)


@router.get(
    "/deliverables/{deliverable_id}/reviews/{review_id}/download", response_class=FileResponse
)
def download_review_attachment(
    deliverable_id: uuid.UUID,
    review_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    deliverable, _ = _load(db, user, deliverable_id, ProjectRole.VIEWER)
    return attached_file_response(storage, deliverables.get_review(db, deliverable, review_id))


@router.put("/documents/{document_id}/visibility", response_model=DocumentPublic)
def set_document_visibility(
    document_id: uuid.UUID, body: VisibilityUpdate, user: CurrentUser, db: DbSession
) -> DocumentPublic:
    """Partage un document de projet avec l'entreprise cliente (responsable du projet)."""
    document = document_service.get_accessible_document(db, user, document_id)
    if document.project_id is not None:
        project_service.get_accessible_project(db, user, document.project_id, ProjectRole.LEAD)
    return document_service.to_public(
        client_documents.set_visibility(db, user, document, body.visibility)
    )


@router.post(
    "/documents/{document_id}/versions",
    response_model=DocumentPublic,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def upload_document_version(
    document_id: uuid.UUID,
    file: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    title: Annotated[str | None, Form(max_length=200)] = None,
) -> DocumentPublic:
    """Nouvelle version d'un document : même groupe, même visibilité."""
    previous = document_service.get_accessible_document(db, user, document_id)
    document = document_service.upload(
        db,
        storage,
        user,
        project_id=previous.project_id,
        title=(title or "").strip() or previous.title,
        kind=previous.kind,
        filename=file.filename or previous.filename,
        source=file.file,
        max_bytes=settings.MAX_UPLOAD_BYTES,
        visibility=previous.visibility,
        previous=previous,
    )
    return document_service.to_public(document)
