import uuid
from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    ChecklistItem,
    Project,
    ProjectMember,
    ProjectPhase,
    Task,
    TaskComment,
    TaskDependency,
    User,
)
from app.models.enums import AccessLevel, NotificationKind, ProjectRole, TaskStatus
from app.schemas.task import (
    ChecklistItemCreate,
    ChecklistItemUpdate,
    TaskCreate,
    TaskUpdate,
)
from app.services import activity_service, notification_service, project_service
from app.services.errors import ConflictError, NotFoundError, ServiceError
from app.services.labels import TASK_STATUS_LABELS

TASK_NOT_FOUND = "Tâche introuvable."
ENTITY = "task"


def get_accessible_task(
    db: Session, user: User, task_id: uuid.UUID, minimum: ProjectRole
) -> tuple[Task, ProjectRole]:
    """Même règle que les projets : sans accès au projet -> 404."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError(TASK_NOT_FOUND)
    try:
        _, role = project_service.get_accessible_project(db, user, task.project_id, minimum)
    except NotFoundError:
        raise NotFoundError(TASK_NOT_FOUND) from None
    return task, role


def list_tasks(
    db: Session,
    project: Project,
    *,
    status: TaskStatus | None = None,
    assignee_id: uuid.UUID | None = None,
    phase_id: uuid.UUID | None = None,
) -> list[Task]:
    statement = select(Task).where(Task.project_id == project.id)
    if status is not None:
        statement = statement.where(Task.status == status)
    if assignee_id is not None:
        statement = statement.where(Task.assignee_id == assignee_id)
    if phase_id is not None:
        statement = statement.where(Task.phase_id == phase_id)
    statement = statement.order_by(Task.due_date.asc().nulls_last(), Task.created_at)
    return list(db.scalars(statement))


# ---------- Validations ----------


def _check_phase(db: Session, project_id: uuid.UUID, phase_id: uuid.UUID | None) -> None:
    if phase_id is None:
        return
    phase = db.get(ProjectPhase, phase_id)
    if phase is None or phase.project_id != project_id:
        raise ServiceError("Cette phase n'appartient pas au projet.")


def check_assignee(db: Session, project_id: uuid.UUID, assignee_id: uuid.UUID | None) -> None:
    if assignee_id is None:
        return
    member = db.scalar(
        select(ProjectMember)
        .join(User, User.id == ProjectMember.user_id)
        .where(
            ProjectMember.project_id == project_id,
            ProjectMember.user_id == assignee_id,
            User.is_active.is_(True),
        )
    )
    if member is None:
        raise ServiceError("La tâche doit être attribuée à un membre du projet.")


def _load_dependencies(
    db: Session, project_id: uuid.UUID, task_id: uuid.UUID | None, ids: Iterable[uuid.UUID]
) -> list[Task]:
    unique_ids = set(ids)
    if task_id in unique_ids:
        raise ServiceError("Une tâche ne peut pas dépendre d'elle-même.")
    tasks = list(db.scalars(select(Task).where(Task.id.in_(unique_ids)))) if unique_ids else []
    if len(tasks) != len(unique_ids) or any(t.project_id != project_id for t in tasks):
        raise ServiceError("Les dépendances doivent être des tâches du même projet.")
    return tasks


def _creates_cycle(db: Session, task_id: uuid.UUID, depends_on: list[Task]) -> bool:
    """Vrai si `task_id` est déjà (transitivement) un prérequis d'une des
    nouvelles dépendances."""
    frontier = {t.id for t in depends_on}
    seen: set[uuid.UUID] = set()
    while frontier:
        if task_id in frontier:
            return True
        seen |= frontier
        frontier = (
            set(
                db.scalars(
                    select(TaskDependency.depends_on_id).where(TaskDependency.task_id.in_(frontier))
                )
            )
            - seen
        )
    return False


def _check_can_complete(task: Task) -> None:
    pending = [d.title for d in task.dependencies if d.status != TaskStatus.DONE]
    if pending:
        raise ConflictError(f"Tâches prérequises non terminées : {', '.join(pending)}.")


# ---------- Tâches ----------


def _notify_assignee(db: Session, actor: User, task: Task) -> None:
    if task.assignee_id is None:
        return
    notification_service.notify(
        db,
        user_id=task.assignee_id,
        actor=actor,
        kind=NotificationKind.TASK_ASSIGNED,
        title=f"{actor.full_name} vous a attribué une tâche",
        body=task.title,
        entity_type="task",
        entity_id=task.id,
    )


def _with_project_access(
    db: Session, project_id: uuid.UUID, user_ids: Iterable[uuid.UUID | None]
) -> list[uuid.UUID]:
    """Ne garde que les membres qui voient encore le projet : un ancien
    membre ne reçoit plus rien sur ses tâches."""
    candidates = {user_id for user_id in user_ids if user_id is not None}
    if not candidates:
        return []
    allowed = set(
        db.scalars(
            select(User.id).where(
                User.id.in_(candidates),
                User.is_active.is_(True),
                (User.access_level == AccessLevel.ADMIN)
                | User.id.in_(
                    select(ProjectMember.user_id).where(ProjectMember.project_id == project_id)
                ),
            )
        )
    )
    return [user_id for user_id in candidates if user_id in allowed]


def _notify_status(db: Session, actor: User, task: Task, *, skip: uuid.UUID | None) -> None:
    """Prévient l'assigné et le créateur ; `skip` vient d'être notifié de
    son attribution."""
    recipients = [uid for uid in (task.assignee_id, task.created_by_id) if uid != skip]
    notification_service.notify_many(
        db,
        user_ids=_with_project_access(db, task.project_id, recipients),
        actor=actor,
        kind=NotificationKind.TASK_STATUS,
        title=f"{actor.full_name} a passé une tâche en « {TASK_STATUS_LABELS[task.status]} »",
        body=task.title,
        entity_type="task",
        entity_id=task.id,
    )


def create_task(db: Session, actor: User, project: Project, data: TaskCreate) -> Task:
    task = build_task(db, actor, project, data)
    db.commit()
    return task


def build_task(
    db: Session,
    actor: User,
    project: Project,
    data: TaskCreate,
    *,
    meeting_id: uuid.UUID | None = None,
    decision_id: uuid.UUID | None = None,
) -> Task:
    """Valide et crée la tâche dans la session, sans commit."""
    _check_phase(db, project.id, data.phase_id)
    check_assignee(db, project.id, data.assignee_id)
    dependencies = _load_dependencies(db, project.id, None, data.depends_on_ids)

    task = Task(
        project_id=project.id,
        created_by_id=actor.id,
        meeting_id=meeting_id,
        decision_id=decision_id,
        **data.model_dump(exclude={"checklist", "depends_on_ids"}),
    )
    task.dependencies = dependencies
    task.checklist = [
        ChecklistItem(label=label.strip(), position=index)
        for index, label in enumerate(data.checklist)
        if label.strip()
    ]
    if task.status == TaskStatus.DONE:
        _check_can_complete(task)
        task.completed_at = datetime.now(UTC)

    db.add(task)
    db.flush()
    _notify_assignee(db, actor, task)
    activity_service.record(
        db,
        actor=actor,
        project_id=project.id,
        entity_type=ENTITY,
        entity_id=task.id,
        action="created",
        changes={"title": task.title, "status": task.status},
    )
    return task


def build_tasks(
    db: Session,
    actor: User,
    project: Project,
    items: list[TaskCreate],
    **origin: uuid.UUID | None,
) -> list[Task]:
    """Crée plusieurs tâches d'un coup (tout ou rien) et commit."""
    tasks = [build_task(db, actor, project, item, **origin) for item in items]
    db.commit()
    return tasks


def update_task(db: Session, actor: User, task: Task, data: TaskUpdate) -> Task:
    changes = data.model_dump(exclude_unset=True)
    if "phase_id" in changes:
        _check_phase(db, task.project_id, changes["phase_id"])
    if "assignee_id" in changes:
        check_assignee(db, task.project_id, changes["assignee_id"])

    new_status = changes.get("status", task.status)
    if new_status == TaskStatus.DONE and task.status != TaskStatus.DONE:
        _check_can_complete(task)
        changes["completed_at"] = datetime.now(UTC)
    elif new_status != TaskStatus.DONE:
        changes["completed_at"] = None

    delta = activity_service.diff(task, changes)
    for field, value in changes.items():
        setattr(task, field, value)
    if "assignee_id" in delta:
        _notify_assignee(db, actor, task)
    if "status" in delta:
        _notify_status(db, actor, task, skip=task.assignee_id if "assignee_id" in delta else None)
    delta.pop("completed_at", None)
    if delta:
        action = "status_changed" if set(delta) == {"status"} else "updated"
        activity_service.record(
            db,
            actor=actor,
            project_id=task.project_id,
            entity_type=ENTITY,
            entity_id=task.id,
            action=action,
            changes=delta,
        )
    db.commit()
    return task


def delete_task(db: Session, actor: User, task: Task) -> None:
    activity_service.record(
        db,
        actor=actor,
        project_id=task.project_id,
        entity_type=ENTITY,
        entity_id=task.id,
        action="deleted",
        changes={"title": task.title},
    )
    db.delete(task)
    db.commit()


def set_dependencies(db: Session, actor: User, task: Task, ids: list[uuid.UUID]) -> Task:
    dependencies = _load_dependencies(db, task.project_id, task.id, ids)
    if _creates_cycle(db, task.id, dependencies):
        raise ConflictError("Ces dépendances créeraient un cycle.")
    task.dependencies = dependencies
    activity_service.record(
        db,
        actor=actor,
        project_id=task.project_id,
        entity_type=ENTITY,
        entity_id=task.id,
        action="dependencies_changed",
        changes={"depends_on": [t.title for t in dependencies]},
    )
    db.commit()
    return task


def list_dependents(db: Session, task: Task) -> list[Task]:
    return list(
        db.scalars(
            select(Task)
            .join(TaskDependency, TaskDependency.task_id == Task.id)
            .where(TaskDependency.depends_on_id == task.id)
        )
    )


# ---------- Checklist ----------


def _get_item(task: Task, item_id: uuid.UUID) -> ChecklistItem:
    item = next((i for i in task.checklist if i.id == item_id), None)
    if item is None:
        raise NotFoundError("Élément de checklist introuvable.")
    return item


def add_checklist_item(db: Session, task: Task, data: ChecklistItemCreate) -> ChecklistItem:
    item = ChecklistItem(task_id=task.id, label=data.label.strip(), position=len(task.checklist))
    db.add(item)
    db.commit()
    db.refresh(task)
    return item


def update_checklist_item(
    db: Session, task: Task, item_id: uuid.UUID, data: ChecklistItemUpdate
) -> ChecklistItem:
    item = _get_item(task, item_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    db.commit()
    return item


def delete_checklist_item(db: Session, task: Task, item_id: uuid.UUID) -> None:
    db.delete(_get_item(task, item_id))
    db.commit()


# ---------- Commentaires ----------


def list_comments(db: Session, task: Task) -> list[TaskComment]:
    return list(
        db.scalars(
            select(TaskComment)
            .where(TaskComment.task_id == task.id)
            .order_by(TaskComment.created_at)
        )
    )


def add_comment(db: Session, author: User, task: Task, body: str) -> TaskComment:
    earlier_authors = db.scalars(
        select(TaskComment.author_id).where(TaskComment.task_id == task.id).distinct()
    )
    followers = [task.assignee_id, task.created_by_id, *earlier_authors]
    comment = TaskComment(task_id=task.id, author_id=author.id, body=body.strip())
    db.add(comment)
    db.flush()
    notification_service.notify_many(
        db,
        user_ids=_with_project_access(db, task.project_id, followers),
        actor=author,
        kind=NotificationKind.TASK_COMMENT,
        title=f"{author.full_name} a commenté « {task.title} »",
        body=comment.body,
        entity_type="task",
        entity_id=task.id,
    )
    activity_service.record(
        db,
        actor=author,
        project_id=task.project_id,
        entity_type=ENTITY,
        entity_id=task.id,
        action="commented",
    )
    db.commit()
    db.refresh(comment)
    return comment
