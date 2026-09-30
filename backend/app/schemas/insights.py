import uuid
from datetime import date

from pydantic import BaseModel

from app.schemas.task import TaskPublic
from app.schemas.user import UserPublic
from app.schemas.work import ProjectAttention


class MemberLoad(BaseModel):
    member: UserPublic
    open_tasks: int
    overdue_tasks: int
    capacity: int  # nombre de tâches ouvertes raisonnable vu la disponibilité
    is_overloaded: bool


class CriticalDependency(BaseModel):
    task: TaskPublic
    waiting_tasks: int  # tâches ouvertes qui attendent celle-ci


class UnexecutedDecision(BaseModel):
    id: uuid.UUID
    title: str
    project_id: uuid.UUID | None
    validated_on: date


class MissingInformation(BaseModel):
    project_id: uuid.UUID
    project_name: str
    issue: str


class AstraHealth(BaseModel):
    """« État de santé d'Astra » (spec §18), limité aux projets visibles."""

    overdue_tasks: list[TaskPublic]
    blocked_tasks: list[TaskPublic]
    critical_dependencies: list[CriticalDependency]
    overloaded_members: list[MemberLoad]
    unexecuted_decisions: list[UnexecutedDecision]
    missing_information: list[MissingInformation]
    projects_at_risk: list[ProjectAttention]


class AssignmentSuggestion(BaseModel):
    member: UserPublic
    score: float
    reasons: list[str]
