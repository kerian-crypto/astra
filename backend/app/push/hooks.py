"""Déclenche les push au commit de la session, jamais avant : une action
annulée (rollback) n'envoie rien.

Toute `Notification` enregistrée part automatiquement en push. Les autres
événements (messages du chat, réponses de Ronda) passent par `enqueue`.
"""

import uuid
from collections.abc import Iterable

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.models import Notification
from app.push import dispatcher
from app.push.message import PushMessage, from_notification

_NOTIFICATIONS_KEY = "astra.push_notifications"
_QUEUED_KEY = "astra.push_queued"


def enqueue(db: Session, user_ids: Iterable[uuid.UUID], message: PushMessage) -> None:
    """Programme un push, envoyé au prochain commit de `db`."""
    recipients = frozenset(user_ids)
    if recipients:
        db.info.setdefault(_QUEUED_KEY, []).append((recipients, message))


def _collect(session: Session, _flush_context: object, _instances: object) -> None:
    created = [obj for obj in session.new if isinstance(obj, Notification)]
    if created:
        session.info.setdefault(_NOTIFICATIONS_KEY, []).extend(created)


def _dispatch(session: Session) -> None:
    for notification in session.info.pop(_NOTIFICATIONS_KEY, []):
        dispatcher.submit({notification.user_id}, from_notification(notification))
    for recipients, message in session.info.pop(_QUEUED_KEY, []):
        dispatcher.submit(recipients, message)


def _discard(session: Session) -> None:
    session.info.pop(_NOTIFICATIONS_KEY, None)
    session.info.pop(_QUEUED_KEY, None)


def install() -> None:
    if not event.contains(Session, "before_flush", _collect):
        event.listen(Session, "before_flush", _collect)
        event.listen(Session, "after_commit", _dispatch)
        event.listen(Session, "after_rollback", _discard)
