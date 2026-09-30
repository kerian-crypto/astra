import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import Priority, TaskStatus
from app.models.user import User


class ProjectPhase(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Étape d'un projet (Analyse, UX/UI, Backend…) regroupant des tâches."""

    __tablename__ = "project_phases"

    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(150))
    description: Mapped[str | None] = mapped_column(Text)
    position: Mapped[int] = mapped_column(Integer, default=0)
    due_date: Mapped[date | None]


class Task(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "tasks"

    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    phase_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("project_phases.id", ondelete="SET NULL"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[TaskStatus] = mapped_column(
        string_enum(TaskStatus), default=TaskStatus.TODO, index=True
    )
    priority: Mapped[Priority] = mapped_column(string_enum(Priority), default=Priority.MEDIUM)
    assignee_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    due_date: Mapped[date | None] = mapped_column(index=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    # Traçabilité : réunion ou décision à l'origine de la tâche.
    meeting_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("meetings.id", ondelete="SET NULL"), index=True
    )
    decision_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("decisions.id", ondelete="SET NULL"), index=True
    )

    assignee: Mapped[User | None] = relationship(foreign_keys=[assignee_id], lazy="joined")
    checklist: Mapped[list["ChecklistItem"]] = relationship(
        cascade="all, delete-orphan", order_by="ChecklistItem.position", lazy="selectin"
    )
    dependencies: Mapped[list["Task"]] = relationship(
        secondary="task_dependencies",
        primaryjoin="Task.id == TaskDependency.task_id",
        secondaryjoin="Task.id == TaskDependency.depends_on_id",
        lazy="selectin",
    )


class TaskDependency(Base):
    """`task_id` ne peut être terminée qu'une fois `depends_on_id` terminée."""

    __tablename__ = "task_dependencies"
    __table_args__ = (CheckConstraint("task_id <> depends_on_id", name="no_self_dependency"),)

    task_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tasks.id", ondelete="CASCADE"), primary_key=True
    )
    depends_on_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tasks.id", ondelete="CASCADE"), primary_key=True, index=True
    )


class ChecklistItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "task_checklist_items"

    task_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tasks.id", ondelete="CASCADE"), index=True
    )
    label: Mapped[str] = mapped_column(String(300))
    is_done: Mapped[bool] = mapped_column(default=False)
    position: Mapped[int] = mapped_column(Integer, default=0)


class TaskComment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "task_comments"

    task_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tasks.id", ondelete="CASCADE"), index=True
    )
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    body: Mapped[str] = mapped_column(Text)

    author: Mapped[User] = relationship(lazy="joined")
