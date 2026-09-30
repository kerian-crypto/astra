import uuid
from datetime import datetime

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from app.models.enums import DecisionStatus, MeetingStatus
from app.schemas.common import PartialUpdate
from app.schemas.user import UserPublic

LongText = Field(default=None, max_length=50_000)


class MeetingPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    project_id: uuid.UUID | None
    title: str
    scheduled_at: datetime
    duration_minutes: int
    location: str | None
    status: MeetingStatus
    created_by_id: uuid.UUID


class DecisionPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    meeting_id: uuid.UUID | None
    project_id: uuid.UUID | None
    title: str
    description: str | None
    status: DecisionStatus
    created_by_id: uuid.UUID
    validated_by_id: uuid.UUID | None
    validated_at: datetime | None
    resulting_project_id: uuid.UUID | None
    created_at: datetime


class MeetingDetail(MeetingPublic):
    agenda: str | None
    minutes: str | None
    participants: list[UserPublic]
    decisions: list[DecisionPublic] = []
    can_edit: bool = False


class MeetingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    project_id: uuid.UUID | None = None
    scheduled_at: AwareDatetime
    duration_minutes: int = Field(default=60, ge=5, le=24 * 60)
    location: str | None = Field(default=None, max_length=200)
    agenda: str | None = LongText
    participant_ids: list[uuid.UUID] = Field(default=[], max_length=100)


class MeetingUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"title", "scheduled_at", "duration_minutes", "status"})

    title: str | None = Field(default=None, min_length=1, max_length=200)
    scheduled_at: AwareDatetime | None = None
    duration_minutes: int | None = Field(default=None, ge=5, le=24 * 60)
    location: str | None = Field(default=None, max_length=200)
    agenda: str | None = LongText
    minutes: str | None = LongText
    status: MeetingStatus | None = None
    participant_ids: list[uuid.UUID] | None = Field(default=None, max_length=100)


class DecisionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=10_000)


class ProjectDecisionCreate(DecisionCreate):
    """Décision prise hors réunion, directement dans un projet."""


class DecisionReview(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: DecisionStatus = Field(description="validated ou rejected")
