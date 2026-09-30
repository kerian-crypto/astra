import uuid
from datetime import UTC, datetime

from sqlalchemy import Select, or_, select
from sqlalchemy.orm import Session

from app.models import Decision, Meeting, Project, ProjectMember, Task, User
from app.models.enums import DecisionStatus, NotificationKind, ProjectRole
from app.schemas.meeting import DecisionCreate
from app.schemas.plan import ProjectPlan
from app.schemas.task import TaskCreate
from app.services import (
    activity_service,
    meeting_service,
    notification_service,
    permissions,
    plan_service,
    project_service,
    task_service,
)
from app.services.errors import ConflictError, NotFoundError, PermissionDeniedError, ServiceError

DECISION_NOT_FOUND = "Décision introuvable."
ENTITY = "decision"


def visible_decisions_statement(user: User) -> Select[tuple[Decision]]:
    statement = select(Decision)
    if permissions.is_admin(user):
        return statement
    return statement.where(
        or_(
            Decision.project_id.in_(permissions.visible_project_ids(user)),
            Decision.meeting_id.in_(meeting_service.visible_meeting_ids(user)),
        )
    )


def _can_review(db: Session, user: User, decision: Decision) -> bool:
    if decision.meeting_id is not None:
        meeting = db.get(Meeting, decision.meeting_id)
        if meeting and meeting_service.can_edit(db, user, meeting):
            return True
    if decision.project_id is not None:
        project = db.get(Project, decision.project_id)
        return permissions.get_project_role(db, user, project) == ProjectRole.LEAD
    return permissions.is_admin(user)


def get_accessible_decision(db: Session, user: User, decision_id: uuid.UUID) -> Decision:
    decision = db.scalar(visible_decisions_statement(user).where(Decision.id == decision_id))
    if decision is None:
        raise NotFoundError(DECISION_NOT_FOUND)
    return decision


def list_decisions(
    db: Session,
    user: User,
    *,
    meeting_id: uuid.UUID | None = None,
    project_id: uuid.UUID | None = None,
    status: DecisionStatus | None = None,
    limit: int = 100,
) -> list[Decision]:
    statement = visible_decisions_statement(user)
    if meeting_id is not None:
        statement = statement.where(Decision.meeting_id == meeting_id)
    if project_id is not None:
        statement = statement.where(Decision.project_id == project_id)
    if status is not None:
        statement = statement.where(Decision.status == status)
    return list(db.scalars(statement.order_by(Decision.created_at.desc()).limit(limit)))


def _record(db: Session, user: User, decision: Decision, action: str, changes: dict) -> None:
    activity_service.record(
        db,
        actor=user,
        project_id=decision.project_id,
        entity_type=ENTITY,
        entity_id=decision.id,
        action=action,
        changes=changes,
    )


def _target(decision: Decision) -> tuple[str, uuid.UUID]:
    """Écran ouvert depuis la notification : la réunion d'origine, sinon le projet."""
    if decision.meeting_id is not None:
        return "meeting", decision.meeting_id
    return "project", decision.project_id


def _reviewer_ids(db: Session, decision: Decision) -> list[uuid.UUID]:
    """Responsables du projet et organisateur de la réunion (cf. `_can_review`)."""
    reviewers: list[uuid.UUID] = []
    if decision.meeting_id is not None:
        meeting = db.get(Meeting, decision.meeting_id)
        if meeting is not None:
            reviewers.append(meeting.created_by_id)
    if decision.project_id is not None:
        reviewers.extend(
            db.scalars(
                select(ProjectMember.user_id).where(
                    ProjectMember.project_id == decision.project_id,
                    ProjectMember.role == ProjectRole.LEAD,
                )
            )
        )
    return reviewers


def _create(db: Session, user: User, data: DecisionCreate, **links: uuid.UUID | None) -> Decision:
    decision = Decision(created_by_id=user.id, **data.model_dump(), **links)
    db.add(decision)
    db.flush()
    _record(db, user, decision, "created", {"title": decision.title})
    entity_type, entity_id = _target(decision)
    if entity_id is not None:
        notification_service.notify_many(
            db,
            user_ids=_reviewer_ids(db, decision),
            actor=user,
            kind=NotificationKind.DECISION_PROPOSED,
            title=f"{user.full_name} propose une décision à valider",
            body=decision.title,
            entity_type=entity_type,
            entity_id=entity_id,
        )
    db.commit()
    return decision


def create_in_meeting(db: Session, user: User, meeting: Meeting, data: DecisionCreate) -> Decision:
    """`meeting` doit avoir été chargée avec `write=True`."""
    return _create(db, user, data, meeting_id=meeting.id, project_id=meeting.project_id)


def create_in_project(
    db: Session, user: User, project_id: uuid.UUID, data: DecisionCreate
) -> Decision:
    project_service.get_accessible_project(db, user, project_id, ProjectRole.CONTRIBUTOR)
    return _create(db, user, data, project_id=project_id)


def review(db: Session, user: User, decision: Decision, status: DecisionStatus) -> Decision:
    if status == DecisionStatus.PROPOSED:
        raise ServiceError("Une décision se valide ou se rejette.")
    if not _can_review(db, user, decision):
        raise PermissionDeniedError("Seul le responsable peut valider cette décision.")
    decision.status = status
    decision.validated_by_id = user.id
    decision.validated_at = datetime.now(UTC)
    _record(db, user, decision, "reviewed", {"status": status})
    entity_type, entity_id = _target(decision)
    if entity_id is not None:
        verdict = "validé" if status == DecisionStatus.VALIDATED else "rejeté"
        notification_service.notify(
            db,
            user_id=decision.created_by_id,
            actor=user,
            kind=NotificationKind.DECISION_REVIEWED,
            title=f"{user.full_name} a {verdict} votre décision",
            body=decision.title,
            entity_type=entity_type,
            entity_id=entity_id,
        )
    db.commit()
    return decision


def _require_validated(decision: Decision) -> None:
    if decision.status != DecisionStatus.VALIDATED:
        raise ConflictError("La décision doit d'abord être validée.")


def to_project(db: Session, user: User, decision: Decision, plan: ProjectPlan) -> Project:
    """Décision → projet opérationnel (spec §9), en une seule transaction."""
    _require_validated(decision)
    if decision.resulting_project_id is not None:
        raise ConflictError("Cette décision a déjà généré un projet.")
    project = plan_service.build_project_from_plan(db, user, plan)
    decision.resulting_project_id = project.id
    _record(db, user, decision, "project_created", {"project": project.name})
    db.commit()
    return project


def to_tasks(db: Session, user: User, decision: Decision, items: list[TaskCreate]) -> list[Task]:
    _require_validated(decision)
    if decision.project_id is None:
        raise ServiceError("Seule une décision rattachée à un projet peut générer des tâches.")
    project, _ = project_service.get_accessible_project(
        db, user, decision.project_id, ProjectRole.CONTRIBUTOR
    )
    return task_service.build_tasks(db, user, project, items, decision_id=decision.id)
