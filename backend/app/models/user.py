from sqlalchemy import Boolean, CheckConstraint, String, false
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import AccessLevel


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (CheckConstraint("availability BETWEEN 0 AND 100", name="availability_range"),)

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    full_name: Mapped[str] = mapped_column(String(120))
    job_title: Mapped[str | None] = mapped_column(String(120))
    photo_url: Mapped[str | None] = mapped_column(String(500))
    access_level: Mapped[AccessLevel] = mapped_column(
        string_enum(AccessLevel), default=AccessLevel.MEMBER
    )
    skills: Mapped[list[str]] = mapped_column(ARRAY(String(60)), default=list)
    availability: Mapped[int] = mapped_column(default=100)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Inscription en libre-service : le compte reste inactif jusqu'à sa
    # validation par un administrateur, qui fixe alors le niveau d'accès.
    pending_approval: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false(), index=True
    )
    requested_access_level: Mapped[AccessLevel | None] = mapped_column(string_enum(AccessLevel))
    # Photo déposée sur le serveur (clé de stockage générée).
    photo_key: Mapped[str | None] = mapped_column(String(80))

    @property
    def public_photo_url(self) -> str | None:
        """URL relative à l'API pour une photo déposée (versionnée pour le
        cache). Les anciennes URL externes ne sont jamais renvoyées : l'app
        joint le jeton de connexion aux requêtes de photos."""
        if self.photo_key:
            return f"users/{self.id}/photo?v={self.photo_key[:8]}"
        return None
