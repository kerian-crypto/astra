import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, File, Form, Query, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, ClientUploadQuota, CurrentClient, DbSession, Storage
from app.api.files import attached_file_response
from app.schemas.client.conversation import ConversationCreate, ConversationView, MessageView
from app.services.client import conversations

router = APIRouter(prefix="/conversations", tags=["client-messages"])


@router.get("", response_model=list[ConversationView])
def list_conversations(account: CurrentClient, db: DbSession) -> list[ConversationView]:
    return [
        conversations.conversation_view(db, c, account.id)
        for c in conversations.list_for_client(db, account)
    ]


@router.post("", response_model=ConversationView, status_code=status.HTTP_201_CREATED)
def start_conversation(
    body: ConversationCreate, account: CurrentClient, db: DbSession
) -> ConversationView:
    conversation = conversations.start_for_client(
        db, account, subject=body.subject, project_id=body.project_id, body=body.body
    )
    return conversations.conversation_view(db, conversation, account.id)


@router.get("/{conversation_id}", response_model=ConversationView)
def read_conversation(
    conversation_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> ConversationView:
    conversation = conversations.get_for_client(db, account, conversation_id)
    return conversations.conversation_view(db, conversation, account.id)


@router.get("/{conversation_id}/messages", response_model=list[MessageView])
def list_messages(
    conversation_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    before: datetime | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[MessageView]:
    conversation = conversations.get_for_client(db, account, conversation_id)
    return [
        conversations.message_view(m, account.id)
        for m in conversations.list_messages(db, conversation, before=before, limit=limit)
    ]


@router.post(
    "/{conversation_id}/messages",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
    dependencies=[ClientUploadQuota],
)
def post_message(
    conversation_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    body: Annotated[str, Form(max_length=10_000)] = "",
    file: Annotated[UploadFile | None, File()] = None,
) -> MessageView:
    conversation = conversations.get_for_client(db, account, conversation_id)
    message = conversations.post_message(
        db,
        storage,
        conversation,
        body=body,
        upload=(file.filename or "fichier", file.file) if file else None,
        max_bytes=settings.MAX_CLIENT_UPLOAD_BYTES,
        account=account,
    )
    return conversations.message_view(message, account.id)


@router.post("/{conversation_id}/read", status_code=status.HTTP_204_NO_CONTENT)
def mark_read(conversation_id: uuid.UUID, account: CurrentClient, db: DbSession) -> None:
    conversation = conversations.get_for_client(db, account, conversation_id)
    conversations.mark_read(db, conversation, account.id)


@router.get("/{conversation_id}/messages/{message_id}/file", response_class=FileResponse)
def download_attachment(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    conversation = conversations.get_for_client(db, account, conversation_id)
    return attached_file_response(storage, conversations.get_message(db, conversation, message_id))
