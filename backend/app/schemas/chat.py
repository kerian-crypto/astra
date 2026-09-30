import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import AttachmentKind, ChannelKind
from app.schemas.common import PartialUpdate
from app.schemas.user import UserPublic

CHANNEL_NAME_PATTERN = r"^[^\s#][^#]*$"


class ChannelPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: ChannelKind
    name: str | None
    description: str | None
    project_id: uuid.UUID | None
    announcements_only: bool
    is_archived: bool
    # Calculés pour l'utilisateur courant.
    display_name: str = ""
    unread_count: int = 0
    last_message_at: datetime | None = None
    can_post: bool = True
    photo_url: str | None = None  # relative à l'API, ou URL externe
    can_manage: bool = False  # peut modifier le canal (nom, photo…)


class ChannelDetail(ChannelPublic):
    members: list[UserPublic] = []


class ChannelCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal[ChannelKind.PUBLIC, ChannelKind.PRIVATE]
    name: str = Field(min_length=1, max_length=80, pattern=CHANNEL_NAME_PATTERN)
    description: str | None = Field(default=None, max_length=500)
    announcements_only: bool = False
    member_ids: list[uuid.UUID] = Field(default=[], max_length=200)


class ChannelUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"name", "is_archived", "announcements_only"})

    name: str | None = Field(
        default=None, min_length=1, max_length=80, pattern=CHANNEL_NAME_PATTERN
    )
    description: str | None = Field(default=None, max_length=500)
    announcements_only: bool | None = None
    is_archived: bool | None = None


class DirectChannelRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: uuid.UUID


class ReactionSummary(BaseModel):
    emoji: str
    count: int
    reacted_by_me: bool


class AttachmentPublic(BaseModel):
    kind: AttachmentKind
    name: str
    content_type: str
    size_bytes: int
    duration_ms: int | None  # messages vocaux et vidéos, indiqué par l'app


class MessagePublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)  # pour `author`

    id: uuid.UUID
    channel_id: uuid.UUID
    author: UserPublic | None
    body: str
    reply_to_id: uuid.UUID | None
    mentioned_user_ids: list[uuid.UUID]
    created_at: datetime
    edited_at: datetime | None
    is_deleted: bool = False
    reactions: list[ReactionSummary] = []
    attachment: AttachmentPublic | None = None


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=10_000)
    reply_to_id: uuid.UUID | None = None
    mentioned_user_ids: list[uuid.UUID] = Field(default=[], max_length=50)


class MessageUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=10_000)
