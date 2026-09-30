"""Ce qui s'est passé récemment dans Astra, vu par un membre donné.

Chaque source réutilise le filtre de visibilité de son module : Ronda voit
l'activité des projets, canaux, réunions et documents que le membre peut
ouvrir, jamais davantage (un admin ne lit pas les messages privés des autres).
"""

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    ActivityLog,
    Channel,
    Decision,
    Document,
    Meeting,
    Message,
    Project,
    ProjectPhase,
    Task,
    User,
)
from app.services import (
    channel_service,
    decision_service,
    document_service,
    meeting_service,
    message_service,
    permissions,
)

MAX_EVENTS = 20
MAX_MESSAGES = 20
MAX_DECISIONS = 8
MAX_MEETINGS = 5
MAX_DOCUMENTS = 5
LINE_TEXT = 200

# Titre lisible des entités citées par le journal d'activité.
_TITLED: dict[str, tuple[Any, Any]] = {
    "task": (Task, Task.title),
    "project": (Project, Project.name),
    "phase": (ProjectPhase, ProjectPhase.name),
    "decision": (Decision, Decision.title),
    "meeting": (Meeting, Meeting.title),
    "document": (Document, Document.title),
}


def _clip(text: str | None, limit: int = LINE_TEXT) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _titles(db: Session, logs: list[ActivityLog]) -> dict[uuid.UUID, str]:
    titles: dict[uuid.UUID, str] = {}
    for entity_type, (model, column) in _TITLED.items():
        ids = {log.entity_id for log in logs if log.entity_type == entity_type}
        if ids:
            titles |= dict(db.execute(select(model.id, column).where(model.id.in_(ids))).all())
    return titles


def _changes(changes: dict[str, Any]) -> str:
    parts = [
        f"{field} : {value['from']} → {value['to']}"
        for field, value in changes.items()
        if isinstance(value, dict) and {"from", "to"} <= value.keys()
    ]
    return f" ({_clip(', '.join(parts))})" if parts else ""


def events(db: Session, user: User) -> list[str]:
    """Journal « qui a fait quoi » des projets visibles."""
    logs = list(
        db.scalars(
            select(ActivityLog)
            .where(ActivityLog.project_id.in_(permissions.visible_project_ids(user)))
            .order_by(ActivityLog.created_at.desc())
            .limit(MAX_EVENTS)
        )
    )
    titles = _titles(db, logs)
    projects = dict(
        db.execute(
            select(Project.id, Project.name).where(Project.id.in_({log.project_id for log in logs}))
        ).all()
    )
    return [
        f"- {log.created_at:%d/%m %H:%M} {log.actor.full_name if log.actor else '?'} : "
        f"{log.entity_type} « {titles.get(log.entity_id, '?')} » {log.action}"
        f"{_changes(log.changes or {})} — projet {projects.get(log.project_id, '?')}"
        for log in logs
    ]


def messages(db: Session, user: User) -> list[str]:
    rows = db.execute(
        select(Message, Channel)
        .join(Channel, Channel.id == Message.channel_id)
        .where(
            Message.channel_id.in_(channel_service.visible_channel_ids(user)),
            Message.deleted_at.is_(None),
        )
        .order_by(Message.created_at.desc())
        .limit(MAX_MESSAGES)
    ).all()
    return [
        f"- {message.created_at:%d/%m %H:%M} [{channel_service.display_name(db, user, channel)}] "
        f"{message.author.full_name if message.author else '?'} : "
        + " ".join(filter(None, [_clip(message.body), message_service.attachment_label(message)]))
        for message, channel in reversed(rows)
    ]


def decisions(db: Session, user: User) -> list[str]:
    recent = db.scalars(
        decision_service.visible_decisions_statement(user)
        .order_by(Decision.updated_at.desc())
        .limit(MAX_DECISIONS)
    )
    return [
        f"- {d.title} ({d.status}) : {_clip(d.description) or 'sans description'}" for d in recent
    ]


def meetings(db: Session, user: User) -> list[str]:
    recent = db.scalars(
        select(Meeting)
        .where(Meeting.id.in_(meeting_service.visible_meeting_ids(user)))
        .order_by(Meeting.updated_at.desc())
        .limit(MAX_MEETINGS)
    )
    return [
        f"- {m.title} le {m.scheduled_at:%d/%m/%Y %H:%M} UTC ({m.status}) : "
        f"{_clip(m.minutes) or 'pas de compte rendu'}"
        for m in recent
    ]


def documents(db: Session, user: User) -> list[str]:
    recent = db.scalars(
        document_service.visible_documents_statement(user)
        .order_by(Document.updated_at.desc())
        .limit(MAX_DOCUMENTS)
    )
    return [f"- {d.title} ({d.kind})" for d in recent]
