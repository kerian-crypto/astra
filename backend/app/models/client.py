"""Entreprises clientes et comptes Astra Client.

Les comptes client vivent dans leur propre table, distincte de `users` : un
compte client n'est jamais un membre d'Astra et ses jetons portent une
audience différente. Les routes d'Astra Hub les refusent donc par construction.
"""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, false
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.client_enums import ClientNotificationKind, InvitationPurpose
from app.models.device import MAX_DEVICE_TOKEN_LENGTH
from app.models.enums import DevicePlatform


class ClientCompany(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "client_companies"

    name: Mapped[str] = mapped_column(String(150))
    email: Mapped[str | None] = mapped_column(String(320))
    phone: Mapped[str | None] = mapped_column(String(40))
    address: Mapped[str | None] = mapped_column(String(300))
    website: Mapped[str | None] = mapped_column(String(300))
    sector: Mapped[str | None] = mapped_column(String(120))
    # Note interne d'Astra sur le client : jamais exposée côté client (§41).
    internal_notes: Mapped[str | None] = mapped_column(Text)
    logo_key: Mapped[str | None] = mapped_column(String(80))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Entreprise créée par une inscription depuis Astra Client (prospect).
    self_registered: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )


class ClientAccount(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "client_accounts"

    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(120))
    job_title: Mapped[str | None] = mapped_column(String(120))
    phone: Mapped[str | None] = mapped_column(String(40))
    # Vide tant que le compte n'est pas activé par le lien d'invitation.
    password_hash: Mapped[str | None] = mapped_column(String(255))
    permissions: Mapped[list[str]] = mapped_column(ARRAY(String(40)), default=list)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    company: Mapped[ClientCompany] = relationship(lazy="joined")

    def has_permission(self, permission: str) -> bool:
        return permission in self.permissions


class ClientInvitation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Lien à usage unique (activation ou nouveau mot de passe), émis depuis
    Astra Hub et transmis au client par le membre. Stocké haché."""

    __tablename__ = "client_invitations"

    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="CASCADE"), index=True
    )
    purpose: Mapped[InvitationPurpose] = mapped_column(string_enum(InvitationPurpose))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )


class ClientRefreshToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Mêmes règles que `RefreshToken` : haché, renouvelé à chaque usage,
    réutilisation = révocation de toute la famille."""

    __tablename__ = "client_refresh_tokens"

    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[uuid.UUID] = mapped_column(index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ClientDeviceToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "client_device_tokens"

    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(MAX_DEVICE_TOKEN_LENGTH), unique=True)
    platform: Mapped[DevicePlatform] = mapped_column(string_enum(DevicePlatform))


class ClientNotification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "client_notifications"

    account_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[ClientNotificationKind] = mapped_column(string_enum(ClientNotificationKind))
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str | None] = mapped_column(String(500))
    # Cible pour la navigation (deep link) côté Astra Client.
    entity_type: Mapped[str] = mapped_column(String(40))
    entity_id: Mapped[uuid.UUID]
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
