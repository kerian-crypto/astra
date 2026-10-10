import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, File, Form, Query, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, CurrentUser, DbSession, Storage, UploadQuota
from app.api.files import attached_file_response
from app.schemas.client.conversation import ConversationHub, HubConversationCreate, MessageView
from app.services.client import conversations

router = APIRouter(prefix="/clients/conversations", tags=["clients"])


@router.get("", response_model=list[ConversationHub])
def list_conversations(
    user: CurrentUser,
    db: DbSession,
    company_id: uuid.UUID | None = None,
    project_id: uuid.UUID | None = None,
) -> list[ConversationHub]:
    return [
        conversations.conversation_hub(db, c, user)
        for c in conversations.list_for_hub(db, user, company_id=company_id, project_id=project_id)
    ]


@router.post("", response_model=ConversationHub, status_code=status.HTTP_201_CREATED)
def start_conversation(
    body: HubConversationCreate, user: CurrentUser, db: DbSession
) -> ConversationHub:
    conversation = conversations.start_for_hub(
        db,
        user,
        company_id=body.company_id,
        subject=body.subject,
        project_id=body.project_id,
        body=body.body,
    )
    return conversations.conversation_hub(db, conversation, user)


@router.get("/{conversation_id}", response_model=ConversationHub)
def read_conversation(
    conversation_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> ConversationHub:
    return conversations.conversation_hub(
        db, conversations.get_for_hub(db, user, conversation_id), user
    )


@router.get("/{conversation_id}/messages", response_model=list[MessageView])
def list_messages(
    conversation_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    before: datetime | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[MessageView]:
    conversation = conversations.get_for_hub(db, user, conversation_id)
    return [
        conversations.message_view(m, user.id)
        for m in conversations.list_messages(db, conversation, before=before, limit=limit)
    ]


@router.post(
    "/{conversation_id}/messages",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def post_message(
    conversation_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    body: Annotated[str, Form(max_length=10_000)] = "",
    file: Annotated[UploadFile | None, File()] = None,
) -> MessageView:
    conversation = conversations.get_for_hub(db, user, conversation_id)
    message = conversations.post_message(
        db,
        storage,
        conversation,
        body=body,
        upload=(file.filename or "fichier", file.file) if file else None,
        max_bytes=settings.MAX_CLIENT_UPLOAD_BYTES,
        user=user,
    )
    return conversations.message_view(message, user.id)


@router.post("/{conversation_id}/read", status_code=status.HTTP_204_NO_CONTENT)
def mark_read(conversation_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    conversations.mark_read(db, conversations.get_for_hub(db, user, conversation_id), user.id)


@router.get("/{conversation_id}/messages/{message_id}/file", response_class=FileResponse)
def download_attachment(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    conversation = conversations.get_for_hub(db, user, conversation_id)
    return attached_file_response(storage, conversations.get_message(db, conversation, message_id))
