import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.attachment import AttachedFileMixin
from app.models.client import ClientAccount
from app.models.client_enums import ConversationKind
from app.models.user import User


class ClientConversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Échange entre une entreprise cliente et Astra (§24).

    Séparé des canaux internes : un client n'apparaît jamais dans le chat
    d'équipe et les discussions internes ne fuient jamais vers le client.
    """

    __tablename__ = "client_conversations"

    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[ConversationKind] = mapped_column(string_enum(ConversationKind))
    subject: Mapped[str] = mapped_column(String(200))
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    deliverable_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("deliverables.id", ondelete="CASCADE")
    )
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("support_tickets.id", ondelete="CASCADE"), unique=True
    )
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


class ClientMessage(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    __tablename__ = "client_messages"
    __table_args__ = (
        # Exactement un auteur : un membre d'Astra ou un compte client.
        CheckConstraint(
            "(author_user_id IS NULL) <> (author_account_id IS NULL)", name="single_author"
        ),
    )

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_conversations.id", ondelete="CASCADE"), index=True
    )
    author_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    author_account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL")
    )
    # Nom affiché figé à l'envoi (un auteur supprimé reste identifiable).
    author_name: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(Text)

    author_user: Mapped[User | None] = relationship(lazy="joined")
    author_account: Mapped[ClientAccount | None] = relationship(lazy="joined")

    @property
    def from_astra(self) -> bool:
        return self.author_account_id is None


class ClientConversationRead(Base):
    """Dernière lecture d'une conversation, par compte client ou par membre."""

    __tablename__ = "client_conversation_reads"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_conversations.id", ondelete="CASCADE"), primary_key=True
    )
    # Identifiant d'un compte client ou d'un membre (UUID distincts).
    reader_id: Mapped[uuid.UUID] = mapped_column(primary_key=True, index=True)
    last_read_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
