import uuid
from typing import Annotated

from fastapi import APIRouter, Body, Query, status

from app.api.deps import CurrentUser, DbSession
from app.api.v1.projects import project_detail
from app.models.enums import DecisionStatus, ProjectRole
from app.schemas.meeting import DecisionCreate, DecisionPublic, DecisionReview
from app.schemas.plan import ProjectPlan
from app.schemas.project import ProjectDetail
from app.schemas.task import TaskCreate, TaskPublic
from app.services import decision_service, project_service

router = APIRouter(tags=["decisions"])

TaskBatch = Annotated[list[TaskCreate], Body(min_length=1, max_length=50)]


@router.get("/decisions", response_model=list[DecisionPublic])
def list_decisions(
    user: CurrentUser,
    db: DbSession,
    project_id: uuid.UUID | None = None,
    status_filter: Annotated[DecisionStatus | None, Query(alias="status")] = None,
) -> list[DecisionPublic]:
    return decision_service.list_decisions(db, user, project_id=project_id, status=status_filter)


@router.post(
    "/projects/{project_id}/decisions",
    response_model=DecisionPublic,
    status_code=status.HTTP_201_CREATED,
)
def create_project_decision(
    project_id: uuid.UUID, body: DecisionCreate, user: CurrentUser, db: DbSession
) -> DecisionPublic:
    return decision_service.create_in_project(db, user, project_id, body)


@router.get("/decisions/{decision_id}", response_model=DecisionPublic)
def read_decision(decision_id: uuid.UUID, user: CurrentUser, db: DbSession) -> DecisionPublic:
    return decision_service.get_accessible_decision(db, user, decision_id)


@router.post("/decisions/{decision_id}/review", response_model=DecisionPublic)
def review_decision(
    decision_id: uuid.UUID, body: DecisionReview, user: CurrentUser, db: DbSession
) -> DecisionPublic:
    decision = decision_service.get_accessible_decision(db, user, decision_id)
    return decision_service.review(db, user, decision, body.status)


@router.post(
    "/decisions/{decision_id}/project",
    response_model=ProjectDetail,
    status_code=status.HTTP_201_CREATED,
)
def decision_to_project(
    decision_id: uuid.UUID, body: ProjectPlan, user: CurrentUser, db: DbSession
) -> ProjectDetail:
    decision = decision_service.get_accessible_decision(db, user, decision_id)
    project = decision_service.to_project(db, user, decision, body)
    _, role = project_service.get_accessible_project(db, user, project.id, ProjectRole.VIEWER)
    return project_detail(project, role)


@router.post(
    "/decisions/{decision_id}/tasks",
    response_model=list[TaskPublic],
    status_code=status.HTTP_201_CREATED,
)
def decision_to_tasks(
    decision_id: uuid.UUID, body: TaskBatch, user: CurrentUser, db: DbSession
) -> list[TaskPublic]:
    decision = decision_service.get_accessible_decision(db, user, decision_id)
    return decision_service.to_tasks(db, user, decision, body)
