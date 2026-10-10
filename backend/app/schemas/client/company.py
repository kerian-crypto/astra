import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.client_enums import ClientPermission
from app.schemas.client.auth import InvitationLink
from app.schemas.common import PartialUpdate
from app.schemas.user import FullName, NormalizedEmail

Phone = Field(default=None, max_length=40)


def _clean_permissions(values: list[ClientPermission]) -> list[ClientPermission]:
    return list(dict.fromkeys(values))


# ---------- Vues Astra Client ----------


class CompanyView(BaseModel):
    """Entreprise vue par ses propres comptes (sans notes internes)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    email: str | None
    phone: str | None
    address: str | None
    website: str | None
    sector: str | None
    has_logo: bool = False


class AccountView(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    full_name: str
    job_title: str | None
    phone: str | None
    permissions: list[ClientPermission]


class MeView(AccountView):
    company: CompanyView


class CompanyUserView(BaseModel):
    """Collègue de la même entreprise (§38)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    job_title: str | None
    email: str
    permissions: list[ClientPermission]
    is_active: bool
    is_activated: bool = False


class MeUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"full_name"})

    full_name: FullName | None = None
    job_title: str | None = Field(default=None, max_length=120)
    phone: str | None = Phone


class CompanyClientUpdate(PartialUpdate):
    """Champs modifiables par le client lui-même. Le nom et l'email de
    l'entreprise restent gérés par Astra (données sensibles, §37)."""

    model_config = ConfigDict(extra="forbid")

    phone: str | None = Phone
    address: str | None = Field(default=None, max_length=300)
    website: str | None = Field(default=None, max_length=300)
    sector: str | None = Field(default=None, max_length=120)


# ---------- Administration (Astra Hub) ----------


class CompanyHub(CompanyView):
    internal_notes: str | None
    is_active: bool
    created_at: datetime
    account_count: int = 0
    project_count: int = 0


class CompanyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=150)
    email: NormalizedEmail | None = None
    phone: str | None = Phone
    address: str | None = Field(default=None, max_length=300)
    website: str | None = Field(default=None, max_length=300)
    sector: str | None = Field(default=None, max_length=120)
    internal_notes: str | None = Field(default=None, max_length=10_000)


class CompanyUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"name", "is_active"})

    name: str | None = Field(default=None, min_length=1, max_length=150)
    email: NormalizedEmail | None = None
    phone: str | None = Phone
    address: str | None = Field(default=None, max_length=300)
    website: str | None = Field(default=None, max_length=300)
    sector: str | None = Field(default=None, max_length=120)
    internal_notes: str | None = Field(default=None, max_length=10_000)
    is_active: bool | None = None


class AccountHub(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    company_id: uuid.UUID
    email: str
    full_name: str
    job_title: str | None
    phone: str | None
    permissions: list[ClientPermission]
    is_active: bool
    activated_at: datetime | None
    last_login_at: datetime | None
    created_at: datetime


class AccountCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: NormalizedEmail
    full_name: FullName
    job_title: str | None = Field(default=None, max_length=120)
    phone: str | None = Phone
    # None = permissions par défaut (consultation, messages, tickets, validation).
    permissions: list[ClientPermission] | None = None

    _dedupe = field_validator("permissions")(
        lambda values: _clean_permissions(values) if values is not None else None
    )


class AccountUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"full_name", "permissions", "is_active"})

    full_name: FullName | None = None
    job_title: str | None = Field(default=None, max_length=120)
    phone: str | None = Phone
    permissions: list[ClientPermission] | None = None
    is_active: bool | None = None

    _dedupe = field_validator("permissions")(
        lambda values: _clean_permissions(values) if values is not None else None
    )


class AccountCreated(BaseModel):
    account: AccountHub
    invitation: InvitationLink
