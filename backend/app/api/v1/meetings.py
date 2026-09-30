import uuid
from typing import Annotated

from fastapi import APIRouter, Body, Query, status
from pydantic import AwareDatetime
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, DbSession
from app.models import Meeting, User
from app.models.enums import MeetingStatus, ProjectRole
from app.schemas.meeting import (
    DecisionCreate,
    DecisionPublic,
    MeetingCreate,
    MeetingDetail,
    MeetingPublic,
    MeetingUpdate,
)
from app.schemas.task import TaskCreate, TaskPublic
from app.services import decision_service, meeting_service, project_service, task_service
from app.services.errors import ServiceError

router = APIRouter(prefix="/meetings", tags=["meetings"])

TaskBatch = Annotated[list[TaskCreate], Body(min_length=1, max_length=50)]


def _detail(db: Session, user: User, meeting: Meeting) -> MeetingDetail:
    detail = MeetingDetail.model_validate(meeting)
    detail.decisions = [
        DecisionPublic.model_validate(d)
        for d in decision_service.list_decisions(db, user, meeting_id=meeting.id)
    ]
    detail.can_edit = meeting_service.can_edit(db, user, meeting)
    return detail


@router.get("", response_model=list[MeetingPublic])
def list_meetings(
    user: CurrentUser,
    db: DbSession,
    start: AwareDatetime | None = None,
    end: AwareDatetime | None = None,
    project_id: uuid.UUID | None = None,
    status_filter: Annotated[MeetingStatus | None, Query(alias="status")] = None,
) -> list[MeetingPublic]:
    return meeting_service.list_meetings(
        db, user, start=start, end=end, project_id=project_id, status=status_filter
    )


@router.post("", response_model=MeetingDetail, status_code=status.HTTP_201_CREATED)
def create_meeting(body: MeetingCreate, user: CurrentUser, db: DbSession) -> MeetingDetail:
    return _detail(db, user, meeting_service.create_meeting(db, user, body))


@router.get("/{meeting_id}", response_model=MeetingDetail)
def read_meeting(meeting_id: uuid.UUID, user: CurrentUser, db: DbSession) -> MeetingDetail:
    return _detail(db, user, meeting_service.get_accessible_meeting(db, user, meeting_id))


@router.patch("/{meeting_id}", response_model=MeetingDetail)
def update_meeting(
    meeting_id: uuid.UUID, body: MeetingUpdate, user: CurrentUser, db: DbSession
) -> MeetingDetail:
    meeting = meeting_service.get_accessible_meeting(db, user, meeting_id, write=True)
    return _detail(db, user, meeting_service.update_meeting(db, user, meeting, body))


@router.delete("/{meeting_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_meeting(meeting_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    meeting = meeting_service.get_accessible_meeting(db, user, meeting_id, write=True)
    meeting_service.delete_meeting(db, user, meeting)


@router.post(
    "/{meeting_id}/decisions", response_model=DecisionPublic, status_code=status.HTTP_201_CREATED
)
def add_decision(
    meeting_id: uuid.UUID, body: DecisionCreate, user: CurrentUser, db: DbSession
) -> DecisionPublic:
    meeting = meeting_service.get_accessible_meeting(db, user, meeting_id, write=True)
    return decision_service.create_in_meeting(db, user, meeting, body)


@router.post(
    "/{meeting_id}/tasks", response_model=list[TaskPublic], status_code=status.HTTP_201_CREATED
)
def create_tasks(
    meeting_id: uuid.UUID, body: TaskBatch, user: CurrentUser, db: DbSession
) -> list[TaskPublic]:
    """Tâches générées par la réunion (après validation du compte rendu)."""
    meeting = meeting_service.get_accessible_meeting(db, user, meeting_id, write=True)
    if meeting.project_id is None:
        raise ServiceError("Rattachez la réunion à un projet pour y créer des tâches.")
    project, _ = project_service.get_accessible_project(
        db, user, meeting.project_id, ProjectRole.CONTRIBUTOR
    )
    return task_service.build_tasks(db, user, project, body, meeting_id=meeting.id)
