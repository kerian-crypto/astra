import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import Priority, TaskStatus
from app.schemas.common import PartialUpdate
from app.schemas.user import UserPublic

Title = Field(min_length=1, max_length=200)
LongText = Field(default=None, max_length=20_000)


# ---------- Phases ----------


class PhasePublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    project_id: uuid.UUID
    name: str
    description: str | None
    position: int
    due_date: date | None


class PhaseCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=150)
    description: str | None = LongText
    position: int | None = Field(default=None, ge=0)
    due_date: date | None = None


class PhaseUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"name", "position"})

    name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = LongText
    position: int | None = Field(default=None, ge=0)
    due_date: date | None = None


# ---------- Tâches ----------


class ChecklistItemPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    label: str
    is_done: bool
    position: int


class TaskDependencyRef(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    status: TaskStatus


class TaskPublic(BaseModel):
    """Vue liste / Kanban."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    project_id: uuid.UUID
    phase_id: uuid.UUID | None
    title: str
    status: TaskStatus
    priority: Priority
    assignee: UserPublic | None
    due_date: date | None
    completed_at: datetime | None
    updated_at: datetime


class TaskDetail(TaskPublic):
    description: str | None
    created_by_id: uuid.UUID
    created_at: datetime
    meeting_id: uuid.UUID | None
    decision_id: uuid.UUID | None
    checklist: list[ChecklistItemPublic]
    dependencies: list[TaskDependencyRef]
    # Tâches qui attendent celle-ci (calculé).
    dependents: list[TaskDependencyRef] = []


class TaskCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Title
    description: str | None = LongText
    phase_id: uuid.UUID | None = None
    status: TaskStatus = TaskStatus.TODO
    priority: Priority = Priority.MEDIUM
    assignee_id: uuid.UUID | None = None
    due_date: date | None = None
    checklist: list[str] = Field(default=[], max_length=50)
    depends_on_ids: list[uuid.UUID] = Field(default=[], max_length=50)


class TaskUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"title", "status", "priority"})

    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = LongText
    phase_id: uuid.UUID | None = None
    status: TaskStatus | None = None
    priority: Priority | None = None
    assignee_id: uuid.UUID | None = None
    due_date: date | None = None


class DependenciesUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    depends_on_ids: list[uuid.UUID] = Field(max_length=50)


class ChecklistItemCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=1, max_length=300)


class ChecklistItemUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"label", "is_done", "position"})

    label: str | None = Field(default=None, min_length=1, max_length=300)
    is_done: bool | None = None
    position: int | None = Field(default=None, ge=0)


class CommentPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    author: UserPublic
    body: str
    created_at: datetime


class CommentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=5_000)


# ---------- Historique ----------


class ActivityPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    project_id: uuid.UUID | None
    actor: UserPublic | None
    entity_type: str
    entity_id: uuid.UUID
    action: str
    changes: dict[str, Any]
    created_at: datetime
