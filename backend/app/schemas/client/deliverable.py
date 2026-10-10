import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from app.models.client_enums import DeliverableStatus, ReviewAction
from app.schemas.client.common import AttachedFile
from app.schemas.common import PartialUpdate


class VersionView(BaseModel):
    id: uuid.UUID
    number: int
    notes: str | None
    link_url: str | None
    file: AttachedFile | None
    published_at: datetime


class ReviewView(BaseModel):
    id: uuid.UUID
    version_number: int
    action: ReviewAction
    reviewer_name: str
    reason: str | None
    comment: str | None
    file: AttachedFile | None
    created_at: datetime


class DeliverableView(BaseModel):
    id: uuid.UUID
    project_id: uuid.UUID
    project_name: str
    title: str
    description: str | None
    status: DeliverableStatus
    requires_validation: bool
    due_date: date | None
    current_version: VersionView | None
    updated_at: datetime


class DeliverableDetailView(DeliverableView):
    versions: list[VersionView]
    reviews: list[ReviewView]
    can_review: bool


# ---------- Astra Hub ----------


class VersionHub(VersionView):
    published_by_name: str | None


class DeliverableHub(DeliverableView):
    created_at: datetime
    versions: list[VersionHub] = []
    reviews: list[ReviewView] = []


class DeliverableCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=10_000)
    requires_validation: bool = True
    due_date: date | None = None


class DeliverableUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"title", "requires_validation"})

    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=10_000)
    requires_validation: bool | None = None
    due_date: date | None = None


LinkUrl = HttpUrl
