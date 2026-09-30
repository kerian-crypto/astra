import uuid
from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models import Notification, User
from app.models.enums import NotificationKind
from app.services.errors import NotFoundError

BODY_PREVIEW_LENGTH = 140


def preview(text: str) -> str:
    text = " ".join(text.split())
    return text if len(text) <= BODY_PREVIEW_LENGTH else text[: BODY_PREVIEW_LENGTH - 1] + "…"


def notify(
    db: Session,
    *,
    user_id: uuid.UUID,
    actor: User | None,
    kind: NotificationKind,
    title: str,
    entity_type: str,
    entity_id: uuid.UUID,
    body: str | None = None,
) -> Notification | None:
    """Ajoute une notification sans commit. On ne se notifie jamais soi-même."""
    if actor is not None and actor.id == user_id:
        return None
    notification = Notification(
        user_id=user_id,
        kind=kind,
        title=title,
        body=preview(body) if body else None,
        entity_type=entity_type,
        entity_id=entity_id,
    )
    db.add(notification)
    return notification


def notify_many(
    db: Session,
    *,
    user_ids: Iterable[uuid.UUID],
    actor: User | None,
    kind: NotificationKind,
    title: str,
    entity_type: str,
    entity_id: uuid.UUID,
    body: str | None = None,
) -> None:
    """Une notification par destinataire distinct, l'auteur exclu."""
    for user_id in dict.fromkeys(user_ids):
        notify(
            db,
            user_id=user_id,
            actor=actor,
            kind=kind,
            title=title,
            entity_type=entity_type,
            entity_id=entity_id,
            body=body,
        )


def list_for_user(
    db: Session, user: User, *, unread_only: bool, limit: int, offset: int
) -> list[Notification]:
    statement = select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        statement = statement.where(Notification.read_at.is_(None))
    return list(
        db.scalars(statement.order_by(Notification.created_at.desc()).limit(limit).offset(offset))
    )


def unread_count(db: Session, user: User) -> int:
    return db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
    )


def mark_read(db: Session, user: User, notification_id: uuid.UUID) -> Notification:
    notification = db.get(Notification, notification_id)
    if notification is None or notification.user_id != user.id:
        raise NotFoundError("Notification introuvable.")
    notification.read_at = notification.read_at or datetime.now(UTC)
    db.commit()
    return notification


def mark_all_read(db: Session, user: User) -> None:
    db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )
    db.commit()
