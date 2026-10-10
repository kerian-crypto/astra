"""Pousse en temps réel toute notification enregistrée, quel que soit le
service qui l'a créée : écoute les commits de session SQLAlchemy."""

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.models import ClientNotification, Notification
from app.realtime.hub import client_hub, publish_from_thread
from app.schemas.client.notification import ClientNotificationView
from app.schemas.notification import NotificationPublic

_PENDING_KEY = "astra.pending_notifications"


def _collect(session: Session, _flush_context: object, _instances: object) -> None:
    created = [obj for obj in session.new if isinstance(obj, Notification | ClientNotification)]
    if created:
        session.info.setdefault(_PENDING_KEY, []).extend(created)


def _publish(session: Session) -> None:
    for notification in session.info.pop(_PENDING_KEY, []):
        if isinstance(notification, ClientNotification):
            publish_from_thread(
                {
                    "type": "notification.created",
                    "notification": ClientNotificationView.model_validate(notification).model_dump(
                        mode="json"
                    ),
                },
                {notification.account_id},
                target=client_hub,
            )
            continue
        publish_from_thread(
            {
                "type": "notification.created",
                "notification": NotificationPublic.model_validate(notification).model_dump(
                    mode="json"
                ),
            },
            {notification.user_id},
        )


def _discard(session: Session) -> None:
    session.info.pop(_PENDING_KEY, None)


def install() -> None:
    if not event.contains(Session, "before_flush", _collect):
        event.listen(Session, "before_flush", _collect)
        event.listen(Session, "after_commit", _publish)
        event.listen(Session, "after_rollback", _discard)
