import uuid

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.enums import DevicePlatform

# Les jetons FCM font ~160 caractères ; la marge couvre leurs évolutions.
MAX_DEVICE_TOKEN_LENGTH = 4096


class DeviceToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Jeton Firebase Cloud Messaging d'un appareil connecté.

    Un jeton identifie une installation de l'application : s'il est enregistré
    par un autre compte (changement d'utilisateur sur le même téléphone), il
    lui est réattribué.
    """

    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(MAX_DEVICE_TOKEN_LENGTH), unique=True)
    platform: Mapped[DevicePlatform] = mapped_column(string_enum(DevicePlatform))
