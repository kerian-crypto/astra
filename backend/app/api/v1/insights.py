import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from app.api.deps import CurrentUser, DbSession
from app.models import ProjectMember
from app.models.enums import ProjectRole
from app.schemas.insights import AssignmentSuggestion, AstraHealth, MemberLoad
from app.schemas.search import SearchHit, SearchType
from app.services import insights_service, project_service, search_service, task_service

router = APIRouter(tags=["insights"])


@router.get("/search", response_model=list[SearchHit])
def search(
    user: CurrentUser,
    db: DbSession,
    q: Annotated[str, Query(min_length=2, max_length=200)],
    types: Annotated[list[SearchType] | None, Query()] = None,
) -> list[SearchHit]:
    return search_service.search(db, user, q, set(types) if types else None)


@router.get("/insights/health", response_model=AstraHealth)
def health(user: CurrentUser, db: DbSession, today: date | None = None) -> AstraHealth:
    return insights_service.health(db, user, today or date.today())


@router.get("/projects/{project_id}/workload", response_model=list[MemberLoad])
def project_workload(
    project_id: uuid.UUID, user: CurrentUser, db: DbSession, today: date | None = None
) -> list[MemberLoad]:
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.VIEWER)
    member_ids = set(
        db.scalars(select(ProjectMember.user_id).where(ProjectMember.project_id == project.id))
    )
    return insights_service.member_loads(
        db, user, today or date.today(), member_ids, project_id=project.id
    )


@router.get("/tasks/{task_id}/assignment-suggestions", response_model=list[AssignmentSuggestion])
def assignment_suggestions(
    task_id: uuid.UUID, user: CurrentUser, db: DbSession, today: date | None = None
) -> list[AssignmentSuggestion]:
    task, _ = task_service.get_accessible_task(db, user, task_id, ProjectRole.CONTRIBUTOR)
    return insights_service.suggest_assignees(db, user, task, today or date.today())
