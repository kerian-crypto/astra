import uuid
from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, ClientUploadQuota, CurrentClient, DbSession, Storage
from app.api.files import attached_file_response
from app.models.client_enums import ReviewAction
from app.schemas.client.conversation import ConversationView
from app.schemas.client.deliverable import DeliverableDetailView, DeliverableView
from app.schemas.client.project import ClientProjectSummary, ClientProjectView, TimelineEvent
from app.services.client import access, conversations, deliverables, projects

router = APIRouter(tags=["client-projects"])


@router.get("/projects", response_model=list[ClientProjectSummary])
def list_projects(account: CurrentClient, db: DbSession) -> list[ClientProjectSummary]:
    return projects.list_projects(db, account)


@router.get("/projects/{project_id}", response_model=ClientProjectView)
def read_project(project_id: uuid.UUID, account: CurrentClient, db: DbSession) -> ClientProjectView:
    return projects.project_view(db, account, access.get_project(db, account, project_id))


@router.get("/projects/{project_id}/timeline", response_model=list[TimelineEvent])
def project_timeline(
    project_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> list[TimelineEvent]:
    return projects.timeline(db, access.get_project(db, account, project_id))


@router.post("/projects/{project_id}/conversation", response_model=ConversationView)
def project_conversation(
    project_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> ConversationView:
    conversation = conversations.project_conversation_for_client(db, account, project_id)
    return conversations.conversation_view(db, conversation, account.id)


@router.get("/deliverables", response_model=list[DeliverableView])
def list_deliverables(
    account: CurrentClient,
    db: DbSession,
    project_id: uuid.UUID | None = None,
    pending_only: bool = False,
) -> list[DeliverableView]:
    return [
        deliverables.to_view(db, d)
        for d in deliverables.list_for_client(
            db, account, project_id=project_id, pending_only=pending_only
        )
    ]


@router.get("/deliverables/{deliverable_id}", response_model=DeliverableDetailView)
def read_deliverable(
    deliverable_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> DeliverableDetailView:
    deliverable = access.get_deliverable(db, account, deliverable_id)
    return deliverables.to_detail_view(db, account, deliverable)


@router.post(
    "/deliverables/{deliverable_id}/reviews",
    response_model=DeliverableDetailView,
    status_code=status.HTTP_201_CREATED,
    dependencies=[ClientUploadQuota],
)
def review_deliverable(
    deliverable_id: uuid.UUID,
    action: Annotated[ReviewAction, Form()],
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    reason: Annotated[str | None, Form(max_length=200)] = None,
    comment: Annotated[str | None, Form(max_length=10_000)] = None,
    file: Annotated[UploadFile | None, File()] = None,
) -> DeliverableDetailView:
    """Approuver, ou demander une modification (motif, commentaire, pièce jointe)."""
    deliverable = access.get_deliverable(db, account, deliverable_id)
    deliverables.review(
        db,
        storage,
        account,
        deliverable,
        action=action,
        reason=reason,
        comment=comment,
        upload=(file.filename or "piece-jointe", file.file) if file else None,
        max_bytes=settings.MAX_CLIENT_UPLOAD_BYTES,
    )
    return deliverables.to_detail_view(db, account, deliverable)


@router.get(
    "/deliverables/{deliverable_id}/versions/{version_id}/download", response_class=FileResponse
)
def download_version(
    deliverable_id: uuid.UUID,
    version_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    version = deliverables.get_version_for_client(db, account, deliverable_id, version_id)
    return attached_file_response(storage, version)


@router.get(
    "/deliverables/{deliverable_id}/reviews/{review_id}/download", response_class=FileResponse
)
def download_review_attachment(
    deliverable_id: uuid.UUID,
    review_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    deliverable = access.get_deliverable(db, account, deliverable_id)
    return attached_file_response(storage, deliverables.get_review(db, deliverable, review_id))
