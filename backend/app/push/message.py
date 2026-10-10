"""Contenu d'une notification push, indépendant du fournisseur (FCM)."""

import uuid
from dataclasses import dataclass, field
from enum import StrEnum

from app.models import ClientNotification, Notification
from app.models.client_enums import ClientNotificationKind
from app.models.enums import NotificationKind


class PushChannel(StrEnum):
    """Canaux de notification Android, créés par l'application
    (MainActivity.kt) : le membre règle chacun séparément dans le système."""

    MESSAGES = "messages"
    ACTIVITY = "activity"


class PushAudience(StrEnum):
    MEMBER = "member"
    CLIENT = "client"


# Type de push sans notification enregistrée (messages du chat, Ronda).
MESSAGE_TYPE = "message"
AI_REPLY_TYPE = "ai_reply"


@dataclass(frozen=True)
class PushMessage:
    title: str
    body: str | None
    # Navigation côté mobile : même convention que les notifications.
    type: str
    entity_type: str
    entity_id: uuid.UUID
    channel: PushChannel = PushChannel.ACTIVITY
    notification_id: uuid.UUID | None = None
    extra: dict[str, str] = field(default_factory=dict)
    # Destinataires : membres (Astra Hub) ou comptes client (Astra Client).
    audience: PushAudience = PushAudience.MEMBER

    def data(self) -> dict[str, str]:
        """Charge utile FCM : uniquement des chaînes."""
        data = {
            "type": self.type,
            "entity_type": self.entity_type,
            "entity_id": str(self.entity_id),
            **self.extra,
        }
        if self.notification_id is not None:
            data["notification_id"] = str(self.notification_id)
        return data


def from_notification(notification: Notification) -> PushMessage:
    channel = (
        PushChannel.MESSAGES
        if notification.kind == NotificationKind.MENTION
        else PushChannel.ACTIVITY
    )
    return PushMessage(
        title=notification.title,
        body=notification.body,
        type=notification.kind.value,
        entity_type=notification.entity_type,
        entity_id=notification.entity_id,
        channel=channel,
        notification_id=notification.id,
    )


def from_client_notification(notification: ClientNotification) -> PushMessage:
    channel = (
        PushChannel.MESSAGES
        if notification.kind == ClientNotificationKind.NEW_MESSAGE
        else PushChannel.ACTIVITY
    )
    return PushMessage(
        title=notification.title,
        body=notification.body,
        type=notification.kind.value,
        entity_type=notification.entity_type,
        entity_id=notification.entity_id,
        channel=channel,
        notification_id=notification.id,
        audience=PushAudience.CLIENT,
    )
