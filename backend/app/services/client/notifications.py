"""Notifications des comptes client. Comme côté Hub, toute notification
enregistrée part en temps réel et en push au commit (voir `push.hooks`)."""

import uuid
from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models import ClientAccount, ClientNotification
from app.models.client_enums import ClientNotificationKind, ClientPermission
from app.services.client import access
from app.services.errors import NotFoundError
from app.services.notification_service import preview


def notify_accounts(
    db: Session,
    account_ids: Iterable[uuid.UUID],
    *,
    kind: ClientNotificationKind,
    title: str,
    entity_type: str,
    entity_id: uuid.UUID,
    body: str | None = None,
    exclude: uuid.UUID | None = None,
) -> None:
    for account_id in dict.fromkeys(account_ids):
        if account_id == exclude:
            continue
        db.add(
            ClientNotification(
                account_id=account_id,
                kind=kind,
                title=title,
                body=preview(body) if body else None,
                entity_type=entity_type,
                entity_id=entity_id,
            )
        )


def notify_company(
    db: Session,
    company_id: uuid.UUID | None,
    permission: ClientPermission | None,
    **kwargs: object,
) -> None:
    """Notifie les comptes de l'entreprise ayant la permission donnée."""
    if company_id is None:
        return
    notify_accounts(db, access.recipients(db, company_id, permission), **kwargs)  # type: ignore[arg-type]


def list_for_account(
    db: Session, account: ClientAccount, *, unread_only: bool, limit: int, offset: int
) -> list[ClientNotification]:
    statement = select(ClientNotification).where(ClientNotification.account_id == account.id)
    if unread_only:
        statement = statement.where(ClientNotification.read_at.is_(None))
    return list(
        db.scalars(
            statement.order_by(ClientNotification.created_at.desc()).limit(limit).offset(offset)
        )
    )


def unread_count(db: Session, account: ClientAccount) -> int:
    return db.scalar(
        select(func.count())
        .select_from(ClientNotification)
        .where(ClientNotification.account_id == account.id, ClientNotification.read_at.is_(None))
    )


def mark_read(
    db: Session, account: ClientAccount, notification_id: uuid.UUID
) -> ClientNotification:
    notification = db.get(ClientNotification, notification_id)
    if notification is None or notification.account_id != account.id:
        raise NotFoundError("Notification introuvable.")
    notification.read_at = notification.read_at or datetime.now(UTC)
    db.commit()
    return notification


def mark_all_read(db: Session, account: ClientAccount) -> None:
    db.execute(
        update(ClientNotification)
        .where(ClientNotification.account_id == account.id, ClientNotification.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )
    db.commit()
