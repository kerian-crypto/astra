import uuid
from datetime import date

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.attachment import AttachedFileMixin
from app.models.client import ClientAccount
from app.models.client_enums import DeliverableStatus, ReviewAction
from app.models.user import User


class Deliverable(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Élément officiellement transmis au client (§18). Invisible du client
    tant qu'aucune version n'est publiée (statut `draft`)."""

    __tablename__ = "deliverables"

    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    requires_validation: Mapped[bool] = mapped_column(default=True)
    status: Mapped[DeliverableStatus] = mapped_column(
        string_enum(DeliverableStatus), default=DeliverableStatus.DRAFT
    )
    due_date: Mapped[date | None]
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    versions: Mapped[list["DeliverableVersion"]] = relationship(
        back_populates="deliverable",
        cascade="all, delete-orphan",
        lazy="selectin",
        order_by="DeliverableVersion.number.desc()",
    )

    @property
    def current_version(self) -> "DeliverableVersion | None":
        return self.versions[0] if self.versions else None


class DeliverableVersion(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    __tablename__ = "deliverable_versions"
    __table_args__ = (UniqueConstraint("deliverable_id", "number", name="deliverable_number"),)

    deliverable_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("deliverables.id", ondelete="CASCADE"), index=True
    )
    number: Mapped[int]
    notes: Mapped[str | None] = mapped_column(Text)
    # Lien externe facultatif (application publiée, maquette en ligne…).
    link_url: Mapped[str | None] = mapped_column(String(500))
    published_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    deliverable: Mapped[Deliverable] = relationship(back_populates="versions")
    published_by: Mapped[User | None] = relationship(lazy="joined")


class DeliverableReview(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    """Validation ou demande de modification d'un client (§19-20).
    Journal en ajout seul : aucune route ne modifie ni ne supprime une ligne."""

    __tablename__ = "deliverable_reviews"

    deliverable_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("deliverables.id", ondelete="CASCADE"), index=True
    )
    version_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("deliverable_versions.id", ondelete="CASCADE")
    )
    # Conservés même si le compte disparaît : la trace reste lisible.
    account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL")
    )
    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE")
    )
    reviewer_name: Mapped[str] = mapped_column(String(120))
    version_number: Mapped[int]
    action: Mapped[ReviewAction] = mapped_column(string_enum(ReviewAction))
    reason: Mapped[str | None] = mapped_column(String(200))
    comment: Mapped[str | None] = mapped_column(Text)

    account: Mapped[ClientAccount | None] = relationship(lazy="joined")
