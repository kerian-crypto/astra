import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import CurrentUser, DbSession
from app.models import Project
from app.models.enums import ProjectRole, ProjectStatus
from app.schemas.plan import ProjectPlan
from app.schemas.project import (
    ProjectCreate,
    ProjectDetail,
    ProjectMemberPublic,
    ProjectMemberUpsert,
    ProjectPublic,
    ProjectUpdate,
)
from app.services import plan_service, project_service

router = APIRouter(prefix="/projects", tags=["projects"])


def project_detail(project: Project, role: ProjectRole) -> ProjectDetail:
    return ProjectDetail.model_validate(
        {
            **ProjectPublic.model_validate(project).model_dump(),
            "members": project.memberships,
            "my_role": role,
        }
    )


@router.get("", response_model=list[ProjectPublic])
def list_projects(
    user: CurrentUser,
    db: DbSession,
    status_filter: Annotated[ProjectStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[ProjectPublic]:
    return project_service.list_projects(db, user, status=status_filter, limit=limit, offset=offset)


@router.post("", response_model=ProjectDetail, status_code=status.HTTP_201_CREATED)
def create_project(body: ProjectCreate, user: CurrentUser, db: DbSession) -> ProjectDetail:
    project = project_service.create_project(db, user, body)
    _, role = project_service.get_accessible_project(db, user, project.id, ProjectRole.VIEWER)
    return project_detail(project, role)


@router.post("/from-plan", response_model=ProjectDetail, status_code=status.HTTP_201_CREATED)
def create_project_from_plan(body: ProjectPlan, user: CurrentUser, db: DbSession) -> ProjectDetail:
    """Validation humaine d'un plan (proposé par ASTRA AI ou rédigé à la main) :
    crée projet, phases et tâches en une seule transaction."""
    project = plan_service.create_project_from_plan(db, user, body)
    _, role = project_service.get_accessible_project(db, user, project.id, ProjectRole.VIEWER)
    return project_detail(project, role)


@router.get("/{project_id}", response_model=ProjectDetail)
def read_project(project_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ProjectDetail:
    project, role = project_service.get_accessible_project(db, user, project_id, ProjectRole.VIEWER)
    return project_detail(project, role)


@router.patch("/{project_id}", response_model=ProjectDetail)
def update_project(
    project_id: uuid.UUID, body: ProjectUpdate, user: CurrentUser, db: DbSession
) -> ProjectDetail:
    project, role = project_service.get_accessible_project(db, user, project_id, ProjectRole.LEAD)
    return project_detail(project_service.update_project(db, user, project, body), role)


@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_project(project_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.LEAD)
    project_service.delete_project(db, project)


@router.put("/{project_id}/members/{user_id}", response_model=ProjectMemberPublic)
def upsert_member(
    project_id: uuid.UUID,
    user_id: uuid.UUID,
    body: ProjectMemberUpsert,
    user: CurrentUser,
    db: DbSession,
) -> ProjectMemberPublic:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.LEAD)
    return project_service.upsert_member(db, user, project, user_id, body.role)


@router.delete("/{project_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(
    project_id: uuid.UUID, user_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> None:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.LEAD)
    project_service.remove_member(db, user, project, user_id)
