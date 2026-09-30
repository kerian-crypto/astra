"""Écran consulté par le membre : Ronda en lit le contenu détaillé.

Chaque lecture passe par la fonction d'accès du module concerné : sans droit
de lecture, l'écran n'est pas décrit (même règle que dans l'app).
"""

from collections.abc import Callable
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Decision, Message, Project, Task, User
from app.models.enums import AIFocusType, ProjectRole
from app.schemas.ai import AIFocus
from app.services import (
    activity_service,
    channel_service,
    decision_service,
    document_service,
    meeting_service,
    message_service,
    task_service,
)
from app.services.errors import NotFoundError, PermissionDeniedError
from app.services.project_service import get_accessible_project

MAX_TASKS = 40
MAX_COMMENTS = 15
MAX_MESSAGES = 40
MAX_ACTIVITY = 15
LONG_TEXT = 3_000
LINE_TEXT = 300


@dataclass(frozen=True)
class FocusView:
    title: str
    lines: list[str]


def _clip(text: str | None, limit: int) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _task_summary(task: Task) -> str:
    assignee = task.assignee.full_name if task.assignee else "non attribuée"
    due = f", échéance {task.due_date.isoformat()}" if task.due_date else ""
    return f"- {task.title} — {task.status}, priorité {task.priority}, {assignee}{due}"


def _history(db: Session, entity_id) -> list[str]:
    return [
        f"- {log.created_at:%d/%m %H:%M} {log.actor.full_name if log.actor else '?'} : "
        f"{log.entity_type} {log.action} {_clip(str(log.changes or ''), LINE_TEXT)}"
        for log in activity_service.list_for_entity(db, entity_id, MAX_ACTIVITY)
    ]


def _project(db: Session, user: User, focus: AIFocus) -> FocusView:
    project, _ = get_accessible_project(db, user, focus.id, ProjectRole.VIEWER)
    tasks = task_service.list_tasks(db, project)
    lines = [
        f"Projet : {project.name} — statut {project.status}, priorité {project.priority}",
        f"Échéance : {project.due_date.isoformat() if project.due_date else 'aucune'}",
        f"Objectif : {_clip(project.objective, LONG_TEXT) or 'non renseigné'}",
        f"Description : {_clip(project.description, LONG_TEXT) or 'non renseignée'}",
        f"Membres : {', '.join(m.user.full_name for m in project.memberships)}",
        f"Tâches ({len(tasks)}) :",
        *(_task_summary(t) for t in tasks[:MAX_TASKS]),
    ]
    logs = activity_service.list_for_project(db, project.id, limit=MAX_ACTIVITY, offset=0)
    lines += ["Historique récent :"] + [
        f"- {log.created_at:%d/%m %H:%M} {log.actor.full_name if log.actor else '?'} : "
        f"{log.entity_type} {log.action}"
        for log in logs
    ]
    return FocusView(project.name, lines)


def _task(db: Session, user: User, focus: AIFocus) -> FocusView:
    task, _ = task_service.get_accessible_task(db, user, focus.id, ProjectRole.VIEWER)
    project = db.get_one(Project, task.project_id)
    lines = [
        f"Tâche du projet {project.name} :",
        _task_summary(task),
        f"Description : {_clip(task.description, LONG_TEXT) or 'aucune'}",
        "Checklist :",
        *(f"- [{'x' if item.is_done else ' '}] {item.label}" for item in task.checklist),
        "Commentaires :",
        *(
            f"- {c.author.full_name} : {_clip(c.body, LINE_TEXT)}"
            for c in task_service.list_comments(db, task)[-MAX_COMMENTS:]
        ),
        "Historique :",
        *_history(db, task.id),
    ]
    return FocusView(task.title, lines)


def _meeting(db: Session, user: User, focus: AIFocus) -> FocusView:
    meeting = meeting_service.get_accessible_meeting(db, user, focus.id)
    decisions = db.scalars(select(Decision).where(Decision.meeting_id == meeting.id))
    lines = [
        f"Réunion : {meeting.title} — {meeting.status}, "
        f"le {meeting.scheduled_at:%d/%m/%Y %H:%M} UTC",
        f"Participants : {', '.join(p.full_name for p in meeting.participants) or 'aucun'}",
        f"Ordre du jour : {_clip(meeting.agenda, LONG_TEXT) or 'aucun'}",
        f"Compte rendu : {_clip(meeting.minutes, LONG_TEXT) or 'pas encore rédigé'}",
        "Décisions :",
        *(f"- {d.title} ({d.status})" for d in decisions),
    ]
    return FocusView(meeting.title, lines)


def _channel(db: Session, user: User, focus: AIFocus) -> FocusView:
    channel = channel_service.get_accessible_channel(db, user, focus.id)
    name = channel_service.display_name(db, user, channel)
    messages = db.scalars(
        select(Message)
        .where(Message.channel_id == channel.id, Message.deleted_at.is_(None))
        .order_by(Message.created_at.desc())
        .limit(MAX_MESSAGES)
    )
    lines = [
        f"Canal : {name} ({channel.kind})",
        "Derniers messages (du plus ancien au plus récent) :",
    ]
    lines += [
        f"- {m.created_at:%d/%m %H:%M} {m.author.full_name if m.author else '?'} : "
        + " ".join(filter(None, [_clip(m.body, LINE_TEXT), message_service.attachment_label(m)]))
        for m in reversed(list(messages))
    ]
    return FocusView(name, lines)


def _document(db: Session, user: User, focus: AIFocus) -> FocusView:
    document = document_service.get_accessible_document(db, user, focus.id)
    lines = [
        f"Document : {document.title} ({document.kind}, {document.filename})",
        f"Contenu : {_clip(document.text_content, LONG_TEXT) or 'contenu non indexé'}",
    ]
    return FocusView(document.title, lines)


def _decision(db: Session, user: User, focus: AIFocus) -> FocusView:
    decision = decision_service.get_accessible_decision(db, user, focus.id)
    lines = [
        f"Décision : {decision.title} ({decision.status})",
        f"Description : {_clip(decision.description, LONG_TEXT) or 'aucune'}",
    ]
    return FocusView(decision.title, lines)


_READERS: dict[AIFocusType, Callable[[Session, User, AIFocus], FocusView]] = {
    AIFocusType.PROJECT: _project,
    AIFocusType.TASK: _task,
    AIFocusType.MEETING: _meeting,
    AIFocusType.CHANNEL: _channel,
    AIFocusType.DOCUMENT: _document,
    AIFocusType.DECISION: _decision,
}


def read(db: Session, user: User, focus: AIFocus) -> FocusView:
    """Lève NotFoundError si le membre ne peut pas ouvrir cet écran."""
    try:
        return _READERS[focus.type](db, user, focus)
    except PermissionDeniedError:
        raise NotFoundError("Écran introuvable.") from None


def describe(db: Session, user: User, focus: AIFocus) -> FocusView | None:
    """Comme `read`, mais sans erreur : l'accès a pu être retiré entre-temps."""
    try:
        return read(db, user, focus)
    except NotFoundError:
        return None
