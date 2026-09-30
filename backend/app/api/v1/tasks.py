import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, DbSession
from app.models import Task
from app.models.enums import ProjectRole, TaskStatus
from app.schemas.task import (
    ActivityPublic,
    ChecklistItemCreate,
    ChecklistItemPublic,
    ChecklistItemUpdate,
    CommentCreate,
    CommentPublic,
    DependenciesUpdate,
    PhaseCreate,
    PhasePublic,
    PhaseUpdate,
    TaskCreate,
    TaskDetail,
    TaskPublic,
    TaskUpdate,
)
from app.services import activity_service, phase_service, project_service, task_service

router = APIRouter(tags=["tasks"])

VIEWER, CONTRIBUTOR, LEAD = ProjectRole.VIEWER, ProjectRole.CONTRIBUTOR, ProjectRole.LEAD


def _detail(db: Session, task: Task) -> TaskDetail:
    detail = TaskDetail.model_validate(task)
    detail.dependents = task_service.list_dependents(db, task)
    return detail


# ---------- Phases ----------


@router.get("/projects/{project_id}/phases", response_model=list[PhasePublic])
def list_phases(project_id: uuid.UUID, user: CurrentUser, db: DbSession) -> list[PhasePublic]:
    project, _ = project_service.get_accessible_project(db, user, project_id, VIEWER)
    return phase_service.list_phases(db, project)


@router.post(
    "/projects/{project_id}/phases", response_model=PhasePublic, status_code=status.HTTP_201_CREATED
)
def create_phase(
    project_id: uuid.UUID, body: PhaseCreate, user: CurrentUser, db: DbSession
) -> PhasePublic:
    project, _ = project_service.get_accessible_project(db, user, project_id, LEAD)
    return phase_service.create_phase(db, user, project, body)


@router.patch("/projects/{project_id}/phases/{phase_id}", response_model=PhasePublic)
def update_phase(
    project_id: uuid.UUID, phase_id: uuid.UUID, body: PhaseUpdate, user: CurrentUser, db: DbSession
) -> PhasePublic:
    project, _ = project_service.get_accessible_project(db, user, project_id, LEAD)
    phase = phase_service.get_phase(db, project, phase_id)
    return phase_service.update_phase(db, user, phase, body)


@router.delete("/projects/{project_id}/phases/{phase_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_phase(
    project_id: uuid.UUID, phase_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> None:
    project, _ = project_service.get_accessible_project(db, user, project_id, LEAD)
    phase_service.delete_phase(db, user, phase_service.get_phase(db, project, phase_id))


# ---------- Tâches d'un projet ----------


@router.get("/projects/{project_id}/tasks", response_model=list[TaskPublic])
def list_tasks(
    project_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    status_filter: Annotated[TaskStatus | None, Query(alias="status")] = None,
    assignee_id: uuid.UUID | None = None,
    phase_id: uuid.UUID | None = None,
) -> list[TaskPublic]:
    project, _ = project_service.get_accessible_project(db, user, project_id, VIEWER)
    return task_service.list_tasks(
        db, project, status=status_filter, assignee_id=assignee_id, phase_id=phase_id
    )


@router.post(
    "/projects/{project_id}/tasks", response_model=TaskDetail, status_code=status.HTTP_201_CREATED
)
def create_task(
    project_id: uuid.UUID, body: TaskCreate, user: CurrentUser, db: DbSession
) -> TaskDetail:
    project, _ = project_service.get_accessible_project(db, user, project_id, CONTRIBUTOR)
    return _detail(db, task_service.create_task(db, user, project, body))


@router.get("/projects/{project_id}/activity", response_model=list[ActivityPublic])
def project_activity(
    project_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[ActivityPublic]:
    project, _ = project_service.get_accessible_project(db, user, project_id, VIEWER)
    return activity_service.list_for_project(db, project.id, limit=limit, offset=offset)


# ---------- Tâche ----------


@router.get("/tasks/{task_id}", response_model=TaskDetail)
def read_task(task_id: uuid.UUID, user: CurrentUser, db: DbSession) -> TaskDetail:
    task, _ = task_service.get_accessible_task(db, user, task_id, VIEWER)
    return _detail(db, task)


@router.patch("/tasks/{task_id}", response_model=TaskDetail)
def update_task(
    task_id: uuid.UUID, body: TaskUpdate, user: CurrentUser, db: DbSession
) -> TaskDetail:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    return _detail(db, task_service.update_task(db, user, task, body))


@router.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    task, _ = task_service.get_accessible_task(db, user, task_id, LEAD)
    task_service.delete_task(db, user, task)


@router.put("/tasks/{task_id}/dependencies", response_model=TaskDetail)
def set_dependencies(
    task_id: uuid.UUID, body: DependenciesUpdate, user: CurrentUser, db: DbSession
) -> TaskDetail:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    return _detail(db, task_service.set_dependencies(db, user, task, body.depends_on_ids))


@router.post(
    "/tasks/{task_id}/checklist",
    response_model=ChecklistItemPublic,
    status_code=status.HTTP_201_CREATED,
)
def add_checklist_item(
    task_id: uuid.UUID, body: ChecklistItemCreate, user: CurrentUser, db: DbSession
) -> ChecklistItemPublic:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    return task_service.add_checklist_item(db, task, body)


@router.patch("/tasks/{task_id}/checklist/{item_id}", response_model=ChecklistItemPublic)
def update_checklist_item(
    task_id: uuid.UUID,
    item_id: uuid.UUID,
    body: ChecklistItemUpdate,
    user: CurrentUser,
    db: DbSession,
) -> ChecklistItemPublic:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    return task_service.update_checklist_item(db, task, item_id, body)


@router.delete("/tasks/{task_id}/checklist/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_checklist_item(
    task_id: uuid.UUID, item_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> None:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    task_service.delete_checklist_item(db, task, item_id)


@router.get("/tasks/{task_id}/comments", response_model=list[CommentPublic])
def list_comments(task_id: uuid.UUID, user: CurrentUser, db: DbSession) -> list[CommentPublic]:
    task, _ = task_service.get_accessible_task(db, user, task_id, VIEWER)
    return task_service.list_comments(db, task)


@router.post(
    "/tasks/{task_id}/comments", response_model=CommentPublic, status_code=status.HTTP_201_CREATED
)
def add_comment(
    task_id: uuid.UUID, body: CommentCreate, user: CurrentUser, db: DbSession
) -> CommentPublic:
    task, _ = task_service.get_accessible_task(db, user, task_id, CONTRIBUTOR)
    return task_service.add_comment(db, user, task, body.body)


@router.get("/tasks/{task_id}/history", response_model=list[ActivityPublic])
def task_history(task_id: uuid.UUID, user: CurrentUser, db: DbSession) -> list[ActivityPublic]:
    task, _ = task_service.get_accessible_task(db, user, task_id, VIEWER)
    return activity_service.list_for_entity(db, task.id)
