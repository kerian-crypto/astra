import uuid

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.client import ClientAccount
from app.models.client_enums import TicketPriority, TicketStatus, TicketType
from app.models.user import User


class SupportTicket(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Demande de support (§34-35). Ses échanges passent par la conversation
    liée (`ClientConversation.ticket_id`)."""

    __tablename__ = "support_tickets"

    number: Mapped[str] = mapped_column(String(20), unique=True)  # SUP-2026-014
    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL")
    )
    created_by_account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL")
    )
    type: Mapped[TicketType] = mapped_column(string_enum(TicketType))
    subject: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text)
    status: Mapped[TicketStatus] = mapped_column(
        string_enum(TicketStatus), default=TicketStatus.NEW
    )
    priority: Mapped[TicketPriority] = mapped_column(
        string_enum(TicketPriority), default=TicketPriority.NORMAL
    )
    assignee_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    created_by: Mapped[ClientAccount | None] = relationship(lazy="joined")
    assignee: Mapped[User | None] = relationship(lazy="joined")
