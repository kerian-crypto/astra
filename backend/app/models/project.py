import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import Priority, ProjectRole, ProjectStatus
from app.models.user import User


class Project(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "projects"

    name: Mapped[str] = mapped_column(String(150))
    description: Mapped[str | None] = mapped_column(Text)
    objective: Mapped[str | None] = mapped_column(Text)
    status: Mapped[ProjectStatus] = mapped_column(
        string_enum(ProjectStatus), default=ProjectStatus.IDEA
    )
    priority: Mapped[Priority] = mapped_column(string_enum(Priority), default=Priority.MEDIUM)
    due_date: Mapped[date | None]
    budget: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))

    memberships: Mapped[list["ProjectMember"]] = relationship(
        back_populates="project", cascade="all, delete-orphan", lazy="selectin"
    )


class ProjectMember(TimestampMixin, Base):
    __tablename__ = "project_members"
    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    role: Mapped[ProjectRole] = mapped_column(
        string_enum(ProjectRole), default=ProjectRole.CONTRIBUTOR
    )

    project: Mapped[Project] = relationship(back_populates="memberships")
    user: Mapped[User] = relationship(lazy="joined")
