import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.attachment import AttachedFileMixin
from app.models.client import ClientAccount
from app.models.client_enums import BriefStatus


class ProjectBrief(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Cahier des charges rempli par le client via le questionnaire de
    cadrage. Enregistré au fil des écrans (brouillon), puis soumis à Astra
    qui en déduit un projet et ses tâches."""

    __tablename__ = "project_briefs"

    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL")
    )
    status: Mapped[BriefStatus] = mapped_column(string_enum(BriefStatus), default=BriefStatus.DRAFT)
    answers: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict)
    # Dernière section atteinte, pour reprendre le questionnaire où il en était.
    current_section: Mapped[str | None] = mapped_column(String(40))
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL")
    )
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    account: Mapped[ClientAccount | None] = relationship(lazy="joined")
    files: Mapped[list["BriefFile"]] = relationship(
        cascade="all, delete-orphan", lazy="selectin", order_by="BriefFile.created_at"
    )


class BriefFile(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    """Image ou document de référence joint à une question du questionnaire."""

    __tablename__ = "brief_files"

    brief_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("project_briefs.id", ondelete="CASCADE"), index=True
    )
    question_id: Mapped[str] = mapped_column(String(40))
