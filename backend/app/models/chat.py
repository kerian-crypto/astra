import uuid
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import AttachmentKind, ChannelKind
from app.models.user import User


class Channel(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "channels"

    kind: Mapped[ChannelKind] = mapped_column(string_enum(ChannelKind), index=True)
    name: Mapped[str | None] = mapped_column(String(80))
    description: Mapped[str | None] = mapped_column(String(500))
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), unique=True
    )
    # Clé unique d'une conversation directe : "<uuid_min>:<uuid_max>".
    direct_key: Mapped[str | None] = mapped_column(String(80), unique=True)
    # Seuls managers et admins publient (ex. #annonces).
    announcements_only: Mapped[bool] = mapped_column(default=False)
    is_archived: Mapped[bool] = mapped_column(default=False)
    # Photo du canal (stockage des avatars) ; les conversations directes
    # affichent celle de l'autre membre.
    photo_key: Mapped[str | None] = mapped_column(String(80))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )


class ChannelMember(Base):
    """Membres des canaux privés et directs ; pour tous les canaux, sert aussi
    à mémoriser la dernière lecture (messages non lus)."""

    __tablename__ = "channel_members"

    channel_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("channels.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    # Faux pour une simple trace de lecture sur un canal public/projet.
    is_member: Mapped[bool] = mapped_column(default=True)
    last_read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(lazy="joined")


class Message(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "messages"

    channel_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("channels.id", ondelete="CASCADE"), index=True
    )
    author_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    body: Mapped[str] = mapped_column(Text)
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("messages.id", ondelete="SET NULL")
    )
    mentioned_user_ids: Mapped[list[uuid.UUID]] = mapped_column(
        ARRAY(UUID(as_uuid=True)), default=list
    )
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Pièce jointe éventuelle (une par message), stockée sous un nom généré.
    attachment_kind: Mapped[AttachmentKind | None] = mapped_column(string_enum(AttachmentKind))
    attachment_key: Mapped[str | None] = mapped_column(String(80), unique=True)
    attachment_name: Mapped[str | None] = mapped_column(String(255))
    attachment_content_type: Mapped[str | None] = mapped_column(String(120))
    attachment_size: Mapped[int | None] = mapped_column(BigInteger)
    attachment_duration_ms: Mapped[int | None] = mapped_column(Integer)

    author: Mapped[User | None] = relationship(lazy="joined")
    reactions: Mapped[list["MessageReaction"]] = relationship(
        cascade="all, delete-orphan", lazy="selectin"
    )


class MessageReaction(Base):
    __tablename__ = "message_reactions"
    message_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("messages.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    emoji: Mapped[str] = mapped_column(String(16), primary_key=True)
