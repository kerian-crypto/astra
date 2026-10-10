import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.client_enums import TicketPriority, TicketStatus, TicketType
from app.schemas.common import PartialUpdate


class TicketView(BaseModel):
    id: uuid.UUID
    number: str
    type: TicketType
    subject: str
    description: str
    status: TicketStatus
    priority: TicketPriority
    project_id: uuid.UUID | None
    project_name: str | None
    created_by_name: str | None
    conversation_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


class TicketHub(TicketView):
    company_id: uuid.UUID
    company_name: str
    assignee_id: uuid.UUID | None
    assignee_name: str | None


class TicketCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: TicketType
    subject: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=10_000)
    project_id: uuid.UUID | None = None
    priority: TicketPriority = TicketPriority.NORMAL


class TicketUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"status", "priority"})

    status: TicketStatus | None = None
    priority: TicketPriority | None = None
    assignee_id: uuid.UUID | None = None
