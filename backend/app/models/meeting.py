import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import DecisionStatus, MeetingStatus
from app.models.user import User


class Meeting(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Réunion, rattachée ou non à un projet (spec §9)."""

    __tablename__ = "meetings"

    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=60)
    location: Mapped[str | None] = mapped_column(String(200))
    agenda: Mapped[str | None] = mapped_column(Text)
    minutes: Mapped[str | None] = mapped_column(Text)  # compte rendu
    status: Mapped[MeetingStatus] = mapped_column(
        string_enum(MeetingStatus), default=MeetingStatus.PLANNED
    )
    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))

    participants: Mapped[list[User]] = relationship(
        secondary="meeting_participants", lazy="selectin", order_by="User.full_name"
    )


class MeetingParticipant(Base):
    __tablename__ = "meeting_participants"

    meeting_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("meetings.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )


class Decision(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Décision prise en réunion ou dans un projet ; peut devenir un projet."""

    __tablename__ = "decisions"
    __table_args__ = (
        CheckConstraint(
            "meeting_id IS NOT NULL OR project_id IS NOT NULL", name="has_meeting_or_project"
        ),
    )

    meeting_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("meetings.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[DecisionStatus] = mapped_column(
        string_enum(DecisionStatus), default=DecisionStatus.PROPOSED, index=True
    )
    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    validated_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    validated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resulting_project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL")
    )
