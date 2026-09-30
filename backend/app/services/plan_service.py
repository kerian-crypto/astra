from sqlalchemy.orm import Session

from app.models import Project, ProjectMember, User
from app.models.enums import ProjectRole, ProjectStatus
from app.schemas.plan import ProjectPlan
from app.schemas.project import ProjectCreate
from app.schemas.task import PhaseCreate, TaskCreate
from app.services import phase_service, project_service, task_service
from app.services.errors import NotFoundError


def build_project_from_plan(db: Session, actor: User, plan: ProjectPlan) -> Project:
    """Crée projet + membres + phases + tâches dans la session, sans commit :
    l'appelant décide du commit (tout ou rien)."""
    project = project_service.build_project(
        db,
        actor,
        # Un projet issu d'un plan démarre en planification.
        ProjectCreate(
            **plan.model_dump(include=set(ProjectCreate.model_fields)),
            status=ProjectStatus.PLANNING,
        ),
    )
    existing = {m.user_id for m in project.memberships}
    added = [user_id for user_id in dict.fromkeys(plan.member_ids) if user_id not in existing]
    for user_id in added:
        user = db.get(User, user_id)
        if user is None or not user.is_active:
            raise NotFoundError("Membre introuvable.")
        project.memberships.append(ProjectMember(user_id=user_id, role=ProjectRole.CONTRIBUTOR))
    db.flush()
    project_service.notify_added_members(db, actor, project, added)

    for index, planned_phase in enumerate(plan.phases):
        phase = phase_service.build_phase(
            db,
            project.id,
            PhaseCreate(
                name=planned_phase.name,
                description=planned_phase.description,
                due_date=planned_phase.due_date,
                position=index,
            ),
        )
        for planned_task in planned_phase.tasks:
            task_service.build_task(
                db,
                actor,
                project,
                TaskCreate(**planned_task.model_dump(), phase_id=phase.id),
            )
    return project


def create_project_from_plan(db: Session, actor: User, plan: ProjectPlan) -> Project:
    project = build_project_from_plan(db, actor, plan)
    db.commit()
    return project
