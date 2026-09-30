"""Signaux d'intelligence collective (spec §14 et §18), calculés sans IA."""

import unicodedata
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import exists, func, select
from sqlalchemy.orm import Session, aliased

from app.models import Decision, Project, ProjectMember, Task, TaskDependency, User
from app.models.enums import DecisionStatus, ProjectRole, ProjectStatus, TaskStatus
from app.schemas.insights import (
    AssignmentSuggestion,
    AstraHealth,
    CriticalDependency,
    MemberLoad,
    MissingInformation,
    UnexecutedDecision,
)
from app.services import decision_service, permissions, work_service

FULL_TIME_CAPACITY = 8  # tâches ouvertes simultanées pour une disponibilité de 100 %
BLOCKING_HORIZON_DAYS = 3
DECISION_EXECUTION_DELAY_DAYS = 7
MIN_WAITING_FOR_CRITICAL = 2
LIST_LIMIT = 20


def capacity(availability: int) -> int:
    return max(1, round(availability / 100 * FULL_TIME_CAPACITY))


def _visible_open_tasks(user: User):
    return select(Task).where(
        Task.status != TaskStatus.DONE,
        Task.project_id.in_(permissions.visible_project_ids(user)),
    )


def _unfinished_dependency():
    prerequisite = aliased(Task)
    return exists().where(
        TaskDependency.task_id == Task.id,
        prerequisite.id == TaskDependency.depends_on_id,
        prerequisite.status != TaskStatus.DONE,
    )


def _blocked_tasks(db: Session, user: User, today: date) -> list[Task]:
    """Tâches qui devraient avancer (commencées ou bientôt dues) mais dont un
    prérequis n'est pas terminé."""
    horizon = today + timedelta(days=BLOCKING_HORIZON_DAYS)
    return list(
        db.scalars(
            _visible_open_tasks(user)
            .where(_unfinished_dependency())
            .where((Task.status != TaskStatus.TODO) | (Task.due_date <= horizon))
            .limit(LIST_LIMIT)
        )
    )


def _critical_dependencies(db: Session, user: User) -> list[CriticalDependency]:
    waiting = aliased(Task)
    count = func.count(waiting.id)
    rows = db.execute(
        _visible_open_tasks(user)
        .add_columns(count)
        .join(TaskDependency, TaskDependency.depends_on_id == Task.id)
        .join(waiting, waiting.id == TaskDependency.task_id)
        .where(waiting.status != TaskStatus.DONE)
        .group_by(Task.id)
        .having(count >= MIN_WAITING_FOR_CRITICAL)
        .order_by(count.desc())
        .limit(LIST_LIMIT)
    ).all()
    return [
        CriticalDependency.model_validate({"task": t, "waiting_tasks": n}, from_attributes=True)
        for t, n in rows
    ]


def member_loads(
    db: Session,
    user: User,
    today: date,
    member_ids: set[uuid.UUID] | None = None,
    project_id: uuid.UUID | None = None,
) -> list[MemberLoad]:
    """Charge de chaque membre, sur les tâches des projets visibles ; limitée
    à un projet si `project_id` est fourni (vue d'un projet donné)."""
    tasks = _visible_open_tasks(user)
    if project_id is not None:
        tasks = tasks.where(Task.project_id == project_id)
    open_tasks = tasks.subquery()
    statement = (
        select(
            User,
            func.count(open_tasks.c.id),
            func.count(open_tasks.c.id).filter(open_tasks.c.due_date < today),
        )
        .outerjoin(open_tasks, open_tasks.c.assignee_id == User.id)
        .where(User.is_active.is_(True))
        .group_by(User.id)
        .order_by(func.count(open_tasks.c.id).desc())
    )
    if member_ids is not None:
        statement = statement.where(User.id.in_(member_ids))
    loads = []
    for member, open_count, overdue_count in db.execute(statement):
        member_capacity = capacity(member.availability)
        loads.append(
            MemberLoad.model_validate(
                {
                    "member": member,
                    "open_tasks": open_count,
                    "overdue_tasks": overdue_count,
                    "capacity": member_capacity,
                    "is_overloaded": open_count > member_capacity,
                },
                from_attributes=True,
            )
        )
    return loads


def _unexecuted_decisions(db: Session, user: User, today: date) -> list[UnexecutedDecision]:
    cutoff = datetime.combine(today, datetime.min.time(), tzinfo=UTC) - timedelta(
        days=DECISION_EXECUTION_DELAY_DAYS
    )
    has_tasks = exists().where(Task.decision_id == Decision.id)
    decisions = db.scalars(
        decision_service.visible_decisions_statement(user)
        .where(
            Decision.status == DecisionStatus.VALIDATED,
            Decision.validated_at < cutoff,
            Decision.resulting_project_id.is_(None),
            ~has_tasks,
        )
        .order_by(Decision.validated_at)
        .limit(LIST_LIMIT)
    )
    return [
        UnexecutedDecision(
            id=d.id, title=d.title, project_id=d.project_id, validated_on=d.validated_at.date()
        )
        for d in decisions
    ]


def _missing_information(db: Session, user: User) -> list[MissingInformation]:
    active = permissions.visible_projects_statement(user).where(
        Project.status == ProjectStatus.ACTIVE
    )
    issues = [
        MissingInformation(project_id=p.id, project_name=p.name, issue="Aucune échéance définie")
        for p in db.scalars(active.where(Project.due_date.is_(None)))
    ]
    unassigned = db.execute(
        active.add_columns(func.count(Task.id))
        .join(Task, Task.project_id == Project.id)
        .where(Task.status != TaskStatus.DONE, Task.assignee_id.is_(None))
        .group_by(Project.id)
    ).all()
    issues += [
        MissingInformation(
            project_id=p.id, project_name=p.name, issue=f"{n} tâche(s) sans responsable"
        )
        for p, n in unassigned
    ]
    return issues[:LIST_LIMIT]


def health(db: Session, user: User, today: date) -> AstraHealth:
    overdue = db.scalars(
        _visible_open_tasks(user)
        .where(Task.due_date < today)
        .order_by(Task.due_date)
        .limit(LIST_LIMIT)
    )
    return AstraHealth.model_validate(
        {
            "overdue_tasks": list(overdue),
            "blocked_tasks": _blocked_tasks(db, user, today),
            "critical_dependencies": _critical_dependencies(db, user),
            "overloaded_members": [m for m in member_loads(db, user, today) if m.is_overloaded],
            "unexecuted_decisions": _unexecuted_decisions(db, user, today),
            "missing_information": _missing_information(db, user),
            "projects_at_risk": work_service.projects_needing_attention(db, user, today),
        },
        from_attributes=True,
    )


# ---------- Répartition du travail (§14) ----------


def _normalize(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def suggest_assignees(
    db: Session, user: User, task: Task, today: date
) -> list[AssignmentSuggestion]:
    """Classe les membres du projet : compétences citées dans la tâche, puis
    capacité restante. L'humain choisit (l'outil propose)."""
    member_ids = set(
        db.scalars(
            select(ProjectMember.user_id).where(
                ProjectMember.project_id == task.project_id,
                ProjectMember.role != ProjectRole.VIEWER,
            )
        )
    )
    haystack = _normalize(f"{task.title} {task.description or ''}")
    suggestions = []
    for load in member_loads(db, user, today, member_ids, project_id=task.project_id):
        matched = [s for s in load.member.skills if _normalize(s) in haystack]
        free = load.capacity - load.open_tasks
        reasons = []
        if matched:
            reasons.append(f"Compétences utiles : {', '.join(matched)}")
        reasons.append(
            f"{load.open_tasks} tâche(s) ouverte(s) pour une capacité de {load.capacity}"
            f" (disponibilité {load.member.availability} %)"
        )
        if load.overdue_tasks:
            reasons.append(f"Déjà {load.overdue_tasks} tâche(s) en retard")
        score = 3 * len(matched) + free - 2 * load.overdue_tasks
        suggestions.append(
            AssignmentSuggestion(member=load.member, score=float(score), reasons=reasons)
        )
    return sorted(suggestions, key=lambda s: s.score, reverse=True)
