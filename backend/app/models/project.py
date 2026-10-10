import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.client_enums import ClientProjectStatus
from app.models.enums import Priority, ProjectRole, ProjectStatus
from app.models.user import User


class Project(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "projects"
    __table_args__ = (
        CheckConstraint("progress IS NULL OR progress BETWEEN 0 AND 100", name="progress_range"),
    )

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

    # Astra Client : nul = projet purement interne, invisible de tout client.
    client_company_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_companies.id", ondelete="SET NULL"), index=True
    )
    # Statut et avancement montrés au client, pilotés par Astra Hub. Nuls :
    # déduits du statut interne et des tâches terminées.
    client_status: Mapped[ClientProjectStatus | None] = mapped_column(
        string_enum(ClientProjectStatus)
    )
    progress: Mapped[int | None]
    client_summary: Mapped[str | None] = mapped_column(Text)

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
