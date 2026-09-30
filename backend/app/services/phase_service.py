import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Project, ProjectPhase, User
from app.schemas.task import PhaseCreate, PhaseUpdate
from app.services import activity_service
from app.services.errors import NotFoundError

ENTITY = "phase"


def list_phases(db: Session, project: Project) -> list[ProjectPhase]:
    return list(
        db.scalars(
            select(ProjectPhase)
            .where(ProjectPhase.project_id == project.id)
            .order_by(ProjectPhase.position, ProjectPhase.created_at)
        )
    )


def get_phase(db: Session, project: Project, phase_id: uuid.UUID) -> ProjectPhase:
    phase = db.get(ProjectPhase, phase_id)
    if phase is None or phase.project_id != project.id:
        raise NotFoundError("Phase introuvable.")
    return phase


def _next_position(db: Session, project_id: uuid.UUID) -> int:
    current = db.scalar(
        select(func.max(ProjectPhase.position)).where(ProjectPhase.project_id == project_id)
    )
    return 0 if current is None else current + 1


def build_phase(db: Session, project_id: uuid.UUID, data: PhaseCreate) -> ProjectPhase:
    """Crée la phase dans la session sans commit (réutilisé par la génération
    de projets à partir d'un plan)."""
    position = data.position if data.position is not None else _next_position(db, project_id)
    phase = ProjectPhase(
        project_id=project_id,
        position=position,
        **data.model_dump(exclude={"position"}),
    )
    db.add(phase)
    db.flush()
    return phase


def create_phase(db: Session, actor: User, project: Project, data: PhaseCreate) -> ProjectPhase:
    phase = build_phase(db, project.id, data)
    activity_service.record(
        db,
        actor=actor,
        project_id=project.id,
        entity_type=ENTITY,
        entity_id=phase.id,
        action="created",
        changes={"name": phase.name},
    )
    db.commit()
    return phase


def update_phase(db: Session, actor: User, phase: ProjectPhase, data: PhaseUpdate) -> ProjectPhase:
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(phase, changes)
    for field, value in changes.items():
        setattr(phase, field, value)
    if delta:
        activity_service.record(
            db,
            actor=actor,
            project_id=phase.project_id,
            entity_type=ENTITY,
            entity_id=phase.id,
            action="updated",
            changes=delta,
        )
    db.commit()
    return phase


def delete_phase(db: Session, actor: User, phase: ProjectPhase) -> None:
    """Les tâches de la phase sont conservées, sans phase (ON DELETE SET NULL)."""
    activity_service.record(
        db,
        actor=actor,
        project_id=phase.project_id,
        entity_type=ENTITY,
        entity_id=phase.id,
        action="deleted",
        changes={"name": phase.name},
    )
    db.delete(phase)
    db.commit()
