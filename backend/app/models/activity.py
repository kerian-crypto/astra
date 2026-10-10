import uuid
from typing import Any

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.user import User


class ActivityLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Historique : qui a fait quoi, quand, sur quel projet (spec §8).

    Journal générique, en ajout seul, partagé par tous les modules.
    """

    __tablename__ = "activity_logs"

    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # Action d'un compte Astra Client (validation, ticket, paiement déclaré…).
    client_account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL"), index=True
    )
    # Nom figé du compte client, lisible dans l'historique côté Hub.
    client_actor_name: Mapped[str | None] = mapped_column(String(120))
    entity_type: Mapped[str] = mapped_column(String(40))
    entity_id: Mapped[uuid.UUID] = mapped_column(index=True)
    action: Mapped[str] = mapped_column(String(40))
    changes: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict)

    actor: Mapped[User | None] = relationship(lazy="joined")
