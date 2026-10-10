import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.client_enums import ConversationKind
from app.schemas.client.common import AttachedFile


class MessageView(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    author_name: str
    from_astra: bool
    is_mine: bool
    body: str
    file: AttachedFile | None
    created_at: datetime


class ConversationView(BaseModel):
    id: uuid.UUID
    kind: ConversationKind
    subject: str
    project_id: uuid.UUID | None
    project_name: str | None
    deliverable_id: uuid.UUID | None
    ticket_id: uuid.UUID | None
    last_message: MessageView | None
    last_message_at: datetime | None
    unread_count: int
    created_at: datetime


class ConversationHub(ConversationView):
    company_id: uuid.UUID
    company_name: str


class ConversationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject: str = Field(min_length=1, max_length=200)
    project_id: uuid.UUID | None = None
    body: str = Field(min_length=1, max_length=10_000)


class HubConversationCreate(ConversationCreate):
    company_id: uuid.UUID
