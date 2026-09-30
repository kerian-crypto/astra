import uuid
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import BinaryIO

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.storage import FileTooLargeError, LocalFileStorage
from app.models import Channel, Message, MessageReaction, User
from app.models.enums import AttachmentKind, ChannelKind, NotificationKind
from app.push import hooks as push_hooks
from app.push.message import MESSAGE_TYPE, PushChannel, PushMessage
from app.schemas.chat import AttachmentPublic, MessageCreate, MessagePublic, ReactionSummary
from app.services import channel_service, file_types, notification_service, permissions
from app.services.errors import ConflictError, NotFoundError, PermissionDeniedError, ServiceError

MESSAGE_NOT_FOUND = "Message introuvable."
ATTACHMENT_NOT_FOUND = "Pièce jointe introuvable."
DELETED_BODY = ""
MAX_ATTACHMENT_NAME = 255

# Libellés lisibles (notifications, contexte de Ronda).
ATTACHMENT_LABELS = {
    AttachmentKind.IMAGE: "photo",
    AttachmentKind.VIDEO: "vidéo",
    AttachmentKind.AUDIO: "message vocal",
    AttachmentKind.FILE: "document",
}


def attachment_label(message: Message) -> str | None:
    """« [photo : plage.jpg] » pour une pièce jointe, sinon None."""
    if message.attachment_kind is None:
        return None
    return f"[{ATTACHMENT_LABELS[message.attachment_kind]} : {message.attachment_name}]"


def to_public(message: Message, viewer: User) -> MessagePublic:
    # Construction explicite : `reactions` est agrégé, pas copié depuis l'ORM.
    public = MessagePublic(
        id=message.id,
        channel_id=message.channel_id,
        author=message.author,
        body=message.body,
        reply_to_id=message.reply_to_id,
        mentioned_user_ids=message.mentioned_user_ids,
        created_at=message.created_at,
        edited_at=message.edited_at,
        attachment=_attachment(message),
    )
    if message.deleted_at is not None:
        public.body = DELETED_BODY
        public.is_deleted = True
        public.mentioned_user_ids = []
        return public
    counts = Counter(r.emoji for r in message.reactions)
    mine = {r.emoji for r in message.reactions if r.user_id == viewer.id}
    public.reactions = [
        ReactionSummary(emoji=emoji, count=count, reacted_by_me=emoji in mine)
        for emoji, count in counts.items()
    ]
    return public


def _attachment(message: Message) -> AttachmentPublic | None:
    if message.attachment_kind is None or message.deleted_at is not None:
        return None
    return AttachmentPublic(
        kind=message.attachment_kind,
        name=message.attachment_name or "",
        content_type=message.attachment_content_type or "application/octet-stream",
        size_bytes=message.attachment_size or 0,
        duration_ms=message.attachment_duration_ms,
    )


def list_messages(
    db: Session, channel: Channel, *, before: datetime | None, limit: int
) -> list[Message]:
    """Pagination par curseur (du plus récent au plus ancien) : robuste avec
    une connexion lente, contrairement à un offset."""
    statement = select(Message).where(Message.channel_id == channel.id)
    if before is not None:
        statement = statement.where(Message.created_at < before)
    return list(db.scalars(statement.order_by(Message.created_at.desc()).limit(limit)))


def get_accessible_message(db: Session, user: User, message_id: uuid.UUID) -> Message:
    message = db.get(Message, message_id)
    if message is None:
        raise NotFoundError(MESSAGE_NOT_FOUND)
    try:
        channel_service.get_accessible_channel(db, user, message.channel_id)
    except NotFoundError:
        raise NotFoundError(MESSAGE_NOT_FOUND) from None
    return message


def _channel_label(channel: Channel) -> str:
    return "un message direct" if channel.kind == ChannelKind.DIRECT else f"#{channel.name}"


def _push_new_message(
    db: Session, author: User, channel: Channel, message: Message, *, skip: set[uuid.UUID]
) -> None:
    """Push à toute l'audience du canal ; `skip` (mentionnés) a déjà reçu
    une notification plus précise."""
    title = (
        author.full_name
        if channel.kind == ChannelKind.DIRECT
        else f"{author.full_name} · #{channel.name}"
    )
    body = message.body or attachment_label(message) or ""
    push_hooks.enqueue(
        db,
        channel_service.recipients(db, channel) - skip - {author.id},
        PushMessage(
            title=title,
            body=notification_service.preview(body) if body else None,
            type=MESSAGE_TYPE,
            entity_type="channel",
            entity_id=channel.id,
            channel=PushChannel.MESSAGES,
        ),
    )


def _check_reply(db: Session, channel: Channel, reply_to_id: uuid.UUID | None) -> None:
    if reply_to_id is not None:
        parent = db.get(Message, reply_to_id)
        if parent is None or parent.channel_id != channel.id:
            raise ServiceError("Le message cité n'appartient pas à cette conversation.")


def post_message(db: Session, user: User, channel: Channel, data: MessageCreate) -> Message:
    channel_service.require_can_post(user, channel)
    _check_reply(db, channel, data.reply_to_id)

    # Les mentions de personnes sans accès au canal sont ignorées : on ne
    # révèle pas le contenu à quelqu'un qui ne peut pas le lire.
    audience = channel_service.recipients(db, channel)
    mentioned = [uid for uid in dict.fromkeys(data.mentioned_user_ids) if uid in audience]
    message = Message(
        channel_id=channel.id,
        author_id=user.id,
        body=data.body.strip(),
        reply_to_id=data.reply_to_id,
        mentioned_user_ids=mentioned,
    )
    db.add(message)
    db.flush()
    for user_id in mentioned:
        notification_service.notify(
            db,
            user_id=user_id,
            actor=user,
            kind=NotificationKind.MENTION,
            title=f"{user.full_name} vous a mentionné dans {_channel_label(channel)}",
            body=message.body,
            entity_type="channel",
            entity_id=channel.id,
        )
    _push_new_message(db, user, channel, message, skip=set(mentioned))
    db.commit()
    channel_service.mark_read(db, user, channel)
    return message


def _safe_filename(filename: str) -> str:
    """Nom affiché : sans chemin ni caractères de contrôle."""
    name = filename.replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(ch for ch in name if ch.isprintable() and ch not in '"<>|:*?')
    return name.strip()[:MAX_ATTACHMENT_NAME] or "fichier"


def post_attachment(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    channel: Channel,
    *,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
    body: str = "",
    duration_ms: int | None = None,
    reply_to_id: uuid.UUID | None = None,
) -> Message:
    """Photo, vidéo, message vocal ou document. Le format est déduit de
    l'extension puis confirmé par la signature du contenu."""
    channel_service.require_can_post(user, channel)
    _check_reply(db, channel, reply_to_id)
    resolved = file_types.resolve_attachment(filename)
    if resolved is None:
        raise ServiceError("Format de fichier non accepté dans le chat.")
    file_type, kind = resolved
    try:
        stored = storage.save(source, max_bytes)
    except FileTooLargeError:
        raise ServiceError(
            f"Fichier trop volumineux (max {max_bytes // (1024 * 1024)} Mo)."
        ) from None
    if stored.size_bytes == 0 or not file_types.matches_signature(file_type, stored.head):
        storage.delete(stored.key)
        raise ServiceError("Le contenu du fichier ne correspond pas à son extension.")

    message = Message(
        channel_id=channel.id,
        author_id=user.id,
        body=body.strip(),
        reply_to_id=reply_to_id,
        mentioned_user_ids=[],
        attachment_kind=kind,
        attachment_key=stored.key,
        attachment_name=_safe_filename(filename),
        attachment_content_type=file_type.content_type,
        attachment_size=stored.size_bytes,
        attachment_duration_ms=duration_ms,
    )
    db.add(message)
    _push_new_message(db, user, channel, message, skip=set())
    try:
        db.commit()
    except Exception:
        db.rollback()
        storage.delete(stored.key)
        raise
    channel_service.mark_read(db, user, channel)
    return message


def attachment_path(storage: LocalFileStorage, message: Message) -> Path:
    """Fichier d'un message déjà chargé avec les contrôles d'accès."""
    if message.attachment_key is None or message.deleted_at is not None:
        raise NotFoundError(ATTACHMENT_NOT_FOUND)
    return storage.path(message.attachment_key)


def edit_message(db: Session, user: User, message: Message, body: str) -> Message:
    if message.author_id != user.id:
        raise PermissionDeniedError("Seul l'auteur peut modifier ce message.")
    if message.deleted_at is not None:
        raise ConflictError("Ce message a été supprimé.")
    message.body = body.strip()
    message.edited_at = datetime.now(UTC)
    db.commit()
    return message


def delete_message(
    db: Session, user: User, message: Message, storage: LocalFileStorage | None = None
) -> Message:
    """Suppression douce : la place du message reste visible dans le fil ; la
    pièce jointe, elle, est effacée du disque."""
    if message.author_id != user.id and not permissions.is_admin(user):
        raise PermissionDeniedError("Seul l'auteur peut supprimer ce message.")
    key = message.attachment_key
    message.deleted_at = message.deleted_at or datetime.now(UTC)
    message.body = DELETED_BODY
    message.reactions = []
    message.attachment_key = None
    db.commit()
    if key and storage:
        storage.delete(key)
    return message


def react(db: Session, user: User, message: Message, emoji: str) -> Message:
    if message.deleted_at is not None:
        raise ConflictError("Ce message a été supprimé.")
    if not any(r.user_id == user.id and r.emoji == emoji for r in message.reactions):
        message.reactions.append(MessageReaction(user_id=user.id, emoji=emoji))
        db.commit()
    return message


def unreact(db: Session, user: User, message: Message, emoji: str) -> Message:
    message.reactions = [
        r for r in message.reactions if not (r.user_id == user.id and r.emoji == emoji)
    ]
    db.commit()
    return message
