import uuid
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, File, Form, Path, Query, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import AwareDatetime
from sqlalchemy.orm import Session

from app.api.deps import AppSettings, CurrentUser, DbSession, PhotoStorage, Storage, UploadQuota
from app.models import Channel, Message, User
from app.models.enums import AttachmentKind
from app.realtime.hub import publish_from_thread
from app.schemas.chat import (
    ChannelCreate,
    ChannelDetail,
    ChannelPublic,
    ChannelUpdate,
    DirectChannelRequest,
    MessageCreate,
    MessagePublic,
    MessageUpdate,
)
from app.services import channel_service, message_service, registration_service
from app.services.errors import NotFoundError

router = APIRouter(tags=["chat"])

EmojiPath = Annotated[str, Path(min_length=1, max_length=16)]


def _detail(db: Session, user: User, channel: Channel) -> ChannelDetail:
    (public,) = channel_service.to_public(db, user, [channel])
    return ChannelDetail(**public.model_dump(), members=channel_service.members(db, channel))


def _broadcast(db: Session, action: str, message: Message, author: User) -> MessagePublic:
    """Diffuse l'événement aux personnes ayant accès au canal et renvoie la
    représentation du message pour l'auteur."""
    channel = db.get(Channel, message.channel_id)
    event: dict = {
        "type": f"message.{action}",
        "channel_id": str(message.channel_id),
        "message_id": str(message.id),
    }
    if action == "created":
        event["message"] = message_service.to_public(message, author).model_dump(mode="json")
    publish_from_thread(event, channel_service.recipients(db, channel))
    return message_service.to_public(message, author)


# ---------- Canaux ----------


@router.get("/channels", response_model=list[ChannelPublic])
def list_channels(
    user: CurrentUser, db: DbSession, include_archived: bool = False
) -> list[ChannelPublic]:
    return channel_service.list_channels(db, user, include_archived=include_archived)


@router.post("/channels", response_model=ChannelDetail, status_code=status.HTTP_201_CREATED)
def create_channel(body: ChannelCreate, user: CurrentUser, db: DbSession) -> ChannelDetail:
    return _detail(db, user, channel_service.create_channel(db, user, body))


@router.post("/channels/direct", response_model=ChannelDetail)
def open_direct(body: DirectChannelRequest, user: CurrentUser, db: DbSession) -> ChannelDetail:
    return _detail(db, user, channel_service.get_or_create_direct(db, user, body.user_id))


@router.get("/projects/{project_id}/channel", response_model=ChannelDetail)
def project_channel(project_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ChannelDetail:
    return _detail(db, user, channel_service.get_or_create_project_channel(db, user, project_id))


@router.get("/channels/{channel_id}", response_model=ChannelDetail)
def read_channel(channel_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ChannelDetail:
    return _detail(db, user, channel_service.get_accessible_channel(db, user, channel_id))


@router.patch("/channels/{channel_id}", response_model=ChannelDetail)
def update_channel(
    channel_id: uuid.UUID, body: ChannelUpdate, user: CurrentUser, db: DbSession
) -> ChannelDetail:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    return _detail(db, user, channel_service.update_channel(db, user, channel, body))


@router.put(
    "/channels/{channel_id}/photo", response_model=ChannelDetail, dependencies=[UploadQuota]
)
def set_channel_photo(
    channel_id: uuid.UUID,
    photo: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: PhotoStorage,
    settings: AppSettings,
) -> ChannelDetail:
    """Photo PNG ou JPEG, par ceux qui gèrent le canal."""
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    channel_service.set_photo(
        db,
        storage,
        user,
        channel,
        photo.filename or "photo",
        photo.file,
        settings.MAX_PHOTO_BYTES,
    )
    return _detail(db, user, channel)


@router.delete("/channels/{channel_id}/photo", response_model=ChannelDetail)
def remove_channel_photo(
    channel_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: PhotoStorage
) -> ChannelDetail:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    return _detail(db, user, channel_service.remove_photo(db, storage, user, channel))


@router.get("/channels/{channel_id}/photo", response_class=FileResponse)
def read_channel_photo(
    channel_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: PhotoStorage
) -> FileResponse:
    """Visible des seules personnes ayant accès au canal."""
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    if not channel.photo_key:
        raise NotFoundError("Photo introuvable.")
    return FileResponse(
        storage.path(channel.photo_key),
        media_type=registration_service.photo_content_type(storage, channel.photo_key),
        headers={
            "X-Content-Type-Options": "nosniff",
            # URL versionnée : la photo peut être mise en cache côté client.
            "Cache-Control": "private, max-age=86400",
        },
    )


@router.put("/channels/{channel_id}/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def add_member(
    channel_id: uuid.UUID, member_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> None:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    channel_service.add_member(db, user, channel, member_id)


@router.delete("/channels/{channel_id}/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(
    channel_id: uuid.UUID, member_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> None:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    channel_service.remove_member(db, user, channel, member_id)


@router.post("/channels/{channel_id}/read", status_code=status.HTTP_204_NO_CONTENT)
def mark_read(channel_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    channel_service.mark_read(
        db, user, channel_service.get_accessible_channel(db, user, channel_id)
    )


# ---------- Messages ----------


@router.get("/channels/{channel_id}/messages", response_model=list[MessagePublic])
def list_messages(
    channel_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    before: AwareDatetime | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[MessagePublic]:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    messages = message_service.list_messages(db, channel, before=before, limit=limit)
    return [message_service.to_public(m, user) for m in messages]


@router.post(
    "/channels/{channel_id}/messages",
    response_model=MessagePublic,
    status_code=status.HTTP_201_CREATED,
)
def post_message(
    channel_id: uuid.UUID, body: MessageCreate, user: CurrentUser, db: DbSession
) -> MessagePublic:
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    message = message_service.post_message(db, user, channel, body)
    return _broadcast(db, "created", message, user)


@router.post(
    "/channels/{channel_id}/attachments",
    response_model=MessagePublic,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def post_attachment(
    channel_id: uuid.UUID,
    file: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    body: Annotated[str, Form(max_length=10_000)] = "",
    duration_ms: Annotated[int | None, Form(ge=0, le=24 * 3600 * 1000)] = None,
    reply_to_id: Annotated[uuid.UUID | None, Form()] = None,
) -> MessagePublic:
    """Photo, vidéo, message vocal ou document, avec légende facultative."""
    channel = channel_service.get_accessible_channel(db, user, channel_id)
    message = message_service.post_attachment(
        db,
        storage,
        user,
        channel,
        filename=file.filename or "fichier",
        source=file.file,
        max_bytes=settings.MAX_CHAT_UPLOAD_BYTES,
        body=body,
        duration_ms=duration_ms,
        reply_to_id=reply_to_id,
    )
    return _broadcast(db, "created", message, user)


@router.get("/messages/{message_id}/attachment", response_class=FileResponse)
def download_attachment(
    message_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    message = message_service.get_accessible_message(db, user, message_id)
    path = message_service.attachment_path(storage, message)
    # Médias en ligne (lecture dans l'app) ; les documents toujours en pièce jointe.
    disposition = "attachment" if message.attachment_kind == AttachmentKind.FILE else "inline"
    return FileResponse(
        path,
        media_type=message.attachment_content_type,
        headers={
            "Content-Disposition": (
                f"{disposition}; filename*=UTF-8''{quote(message.attachment_name or 'fichier')}"
            ),
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, max-age=86400",
        },
    )


@router.patch("/messages/{message_id}", response_model=MessagePublic)
def edit_message(
    message_id: uuid.UUID, body: MessageUpdate, user: CurrentUser, db: DbSession
) -> MessagePublic:
    message = message_service.get_accessible_message(db, user, message_id)
    return _broadcast(
        db, "updated", message_service.edit_message(db, user, message, body.body), user
    )


@router.delete("/messages/{message_id}", response_model=MessagePublic)
def delete_message(
    message_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> MessagePublic:
    message = message_service.get_accessible_message(db, user, message_id)
    deleted = message_service.delete_message(db, user, message, storage)
    return _broadcast(db, "deleted", deleted, user)


@router.put("/messages/{message_id}/reactions/{emoji}", response_model=MessagePublic)
def react(
    message_id: uuid.UUID, emoji: EmojiPath, user: CurrentUser, db: DbSession
) -> MessagePublic:
    message = message_service.get_accessible_message(db, user, message_id)
    return _broadcast(db, "updated", message_service.react(db, user, message, emoji), user)


@router.delete("/messages/{message_id}/reactions/{emoji}", response_model=MessagePublic)
def unreact(
    message_id: uuid.UUID, emoji: EmojiPath, user: CurrentUser, db: DbSession
) -> MessagePublic:
    message = message_service.get_accessible_message(db, user, message_id)
    return _broadcast(db, "updated", message_service.unreact(db, user, message, emoji), user)
