from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import Select, case, func, or_, select
from sqlalchemy.orm import Session

from app.models import Project, Task, User
from app.models.enums import Priority, ProjectStatus, TaskStatus
from app.schemas.work import AstraStats, Dashboard, MyStats, MyWork, ProjectAttention
from app.services import meeting_service, notification_service, permissions

UPCOMING_DAYS = 7
MAX_ITEMS_PER_SECTION = 50
OPEN_PROJECT_STATUSES = (ProjectStatus.PLANNING, ProjectStatus.ACTIVE, ProjectStatus.REVIEW)

# Les priorités sont stockées en texte : l'ordre alphabétique serait faux.
PRIORITY_RANK = case(
    {Priority.CRITICAL: 0, Priority.HIGH: 1, Priority.MEDIUM: 2, Priority.LOW: 3},
    value=Task.priority,
)


def _open_tasks(user: User) -> Select[tuple[Task]]:
    """Tâches non terminées des projets visibles par l'utilisateur."""
    return select(Task).where(
        Task.status != TaskStatus.DONE,
        Task.project_id.in_(permissions.visible_project_ids(user)),
    )


def _my_open_tasks(user: User) -> Select[tuple[Task]]:
    return _open_tasks(user).where(Task.assignee_id == user.id)


def _fetch(db: Session, statement: Select[tuple[Task]]) -> list[Task]:
    ordered = statement.order_by(Task.due_date.asc().nulls_last(), PRIORITY_RANK)
    return list(db.scalars(ordered.limit(MAX_ITEMS_PER_SECTION)))


def _count(db: Session, statement: Select) -> int:
    return db.scalar(select(func.count()).select_from(statement.subquery()))


def _today_filter(today: date):
    return or_(Task.due_date == today, Task.status == TaskStatus.IN_PROGRESS)


def _day_start(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=UTC)


def my_work(db: Session, user: User, today: date) -> MyWork:
    mine = _my_open_tasks(user)
    return MyWork.model_validate(
        {
            "today": _fetch(db, mine.where(_today_filter(today))),
            "overdue": _fetch(db, mine.where(Task.due_date < today)),
            "priority": _fetch(
                db, mine.where(Task.priority.in_([Priority.HIGH, Priority.CRITICAL]))
            ),
            "upcoming": _fetch(
                db,
                mine.where(
                    Task.due_date > today, Task.due_date <= today + timedelta(days=UPCOMING_DAYS)
                ),
            ),
            "meetings": meeting_service.my_upcoming_meetings(
                db, user, _day_start(today), _day_start(today + timedelta(days=UPCOMING_DAYS))
            ),
        },
        from_attributes=True,
    )


def projects_needing_attention(db: Session, user: User, today: date) -> list[ProjectAttention]:
    overdue_counts = (
        _open_tasks(user)
        .where(Task.due_date < today)
        .with_only_columns(Task.project_id, func.count().label("overdue"))
        .group_by(Task.project_id)
        .subquery()
    )
    rows = db.execute(
        permissions.visible_projects_statement(user)
        .add_columns(func.coalesce(overdue_counts.c.overdue, 0))
        .outerjoin(overdue_counts, overdue_counts.c.project_id == Project.id)
        .where(
            Project.status.in_(OPEN_PROJECT_STATUSES),
            or_(overdue_counts.c.overdue > 0, Project.due_date < today),
        )
        .order_by(Project.due_date.asc().nulls_last())
    ).all()
    return [
        ProjectAttention(
            id=project.id,
            name=project.name,
            status=project.status,
            due_date=project.due_date,
            overdue_tasks=overdue,
            reason=(
                "Échéance du projet dépassée"
                if project.due_date and project.due_date < today
                else f"{overdue} tâche(s) en retard"
            ),
        )
        for project, overdue in rows
    ]


def dashboard(db: Session, user: User, today: date) -> Dashboard:
    mine = _my_open_tasks(user)
    visible_projects = permissions.visible_projects_statement(user)
    return Dashboard(
        me=MyStats(
            open_tasks=_count(db, mine),
            today_tasks=_count(db, mine.where(_today_filter(today))),
            overdue_tasks=_count(db, mine.where(Task.due_date < today)),
            unread_notifications=notification_service.unread_count(db, user),
            upcoming_meetings=len(
                meeting_service.my_upcoming_meetings(
                    db, user, _day_start(today), _day_start(today + timedelta(days=1))
                )
            ),
        ),
        astra=AstraStats(
            active_projects=_count(
                db, visible_projects.where(Project.status == ProjectStatus.ACTIVE)
            ),
            open_tasks=_count(db, _open_tasks(user)),
            overdue_tasks=_count(db, _open_tasks(user).where(Task.due_date < today)),
            projects_needing_attention=projects_needing_attention(db, user, today),
        ),
    )
