import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import Priority, ProjectRole, ProjectStatus
from app.schemas.common import PartialUpdate
from app.schemas.user import UserPublic


class ProjectMemberPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user: UserPublic
    role: ProjectRole


class ProjectPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    description: str | None
    objective: str | None
    status: ProjectStatus
    priority: Priority
    due_date: date | None
    budget: Decimal | None
    created_by_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ProjectDetail(ProjectPublic):
    members: list[ProjectMemberPublic]
    my_role: ProjectRole


class ProjectCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=10_000)
    objective: str | None = Field(default=None, max_length=10_000)
    status: ProjectStatus = ProjectStatus.IDEA
    priority: Priority = Priority.MEDIUM
    due_date: date | None = None
    budget: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    # Responsable du projet ; par défaut le créateur.
    lead_id: uuid.UUID | None = None


class ProjectUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"name", "status", "priority"})

    name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=10_000)
    objective: str | None = Field(default=None, max_length=10_000)
    status: ProjectStatus | None = None
    priority: Priority | None = None
    due_date: date | None = None
    budget: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)


class ProjectMemberUpsert(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: ProjectRole = ProjectRole.CONTRIBUTOR
