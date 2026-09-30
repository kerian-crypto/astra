import uuid
from datetime import date

from pydantic import BaseModel

from app.models.enums import ProjectStatus
from app.schemas.meeting import MeetingPublic
from app.schemas.task import TaskPublic


class MyWork(BaseModel):
    """Espace « MON TRAVAIL » (spec §8)."""

    today: list[TaskPublic]
    overdue: list[TaskPublic]
    priority: list[TaskPublic]
    upcoming: list[TaskPublic]
    meetings: list[MeetingPublic] = []


class ProjectAttention(BaseModel):
    id: uuid.UUID
    name: str
    status: ProjectStatus
    due_date: date | None
    overdue_tasks: int
    reason: str


class MyStats(BaseModel):
    open_tasks: int
    today_tasks: int
    overdue_tasks: int
    upcoming_meetings: int = 0
    unread_notifications: int = 0


class AstraStats(BaseModel):
    active_projects: int
    open_tasks: int
    overdue_tasks: int
    projects_needing_attention: list[ProjectAttention]


class Dashboard(BaseModel):
    me: MyStats
    astra: AstraStats
