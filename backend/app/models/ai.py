import uuid
from typing import Any

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import AIFocusType, AIMessageStatus, AIRole


class AIConversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Historique ASTRA AI d'un membre : visible par lui seul."""

    __tablename__ = "ai_conversations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(120))

    messages: Mapped[list["AIMessage"]] = relationship(
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="AIMessage.created_at",
        lazy="selectin",
    )


class AIMessage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "ai_messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ai_conversations.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[AIRole] = mapped_column(string_enum(AIRole))
    content: Mapped[str] = mapped_column(Text, default="")
    # Sources citées par Ronda (schéma app.schemas.ai.Source).
    sources: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    status: Mapped[AIMessageStatus] = mapped_column(string_enum(AIMessageStatus), index=True)
    # Question posée depuis un écran (projet, tâche…) : Ronda lit cet écran.
    focus_type: Mapped[AIFocusType | None] = mapped_column(string_enum(AIFocusType))
    focus_id: Mapped[uuid.UUID | None]
    focus_title: Mapped[str | None] = mapped_column(String(200))
    # Action proposée par Ronda (schéma app.schemas.ai.ProposedAction).
    action: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
