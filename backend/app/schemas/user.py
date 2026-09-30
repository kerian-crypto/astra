import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field

from app.models.enums import AccessLevel
from app.schemas.common import PartialUpdate

MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128
MAX_SKILLS = 30


def _normalize_email(value: str) -> str:
    return value.strip().lower()


def _normalize_skills(values: list[str]) -> list[str]:
    cleaned = [v.strip() for v in values if v.strip()]
    # dédoublonnage en conservant l'ordre
    return list(dict.fromkeys(cleaned))


NormalizedEmail = Annotated[EmailStr, AfterValidator(_normalize_email)]
Password = Annotated[str, Field(min_length=MIN_PASSWORD_LENGTH, max_length=MAX_PASSWORD_LENGTH)]
FullName = Annotated[str, Field(min_length=1, max_length=120)]
Skills = Annotated[
    list[Annotated[str, Field(max_length=60)]],
    Field(max_length=MAX_SKILLS),
    AfterValidator(_normalize_skills),
]
Availability = Annotated[int, Field(ge=0, le=100)]


class UserPublic(BaseModel):
    """Profil visible par tous les membres d'Astra."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    full_name: str
    job_title: str | None
    # Photo déposée (chemin relatif à l'API) ou URL externe.
    photo_url: str | None = Field(validation_alias="public_photo_url")
    access_level: AccessLevel
    skills: list[str]
    availability: int
    is_active: bool
    created_at: datetime


class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: NormalizedEmail
    password: Password
    full_name: FullName
    job_title: str | None = Field(default=None, max_length=120)
    access_level: AccessLevel = AccessLevel.MEMBER
    skills: Skills = []
    availability: Availability = 100


class UserSelfUpdate(PartialUpdate):
    """Champs qu'un membre peut modifier sur son propre profil."""

    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"full_name", "skills", "availability", "access_level", "is_active"})

    full_name: FullName | None = None
    job_title: str | None = Field(default=None, max_length=120)
    # Pas de photo_url : une URL externe ferait envoyer le jeton de chaque
    # lecteur à un site tiers. Les photos passent par PUT /users/me/photo.
    skills: Skills | None = None
    availability: Availability | None = None


class UserAdminUpdate(UserSelfUpdate):
    """Champs supplémentaires réservés aux administrateurs."""

    access_level: AccessLevel | None = None
    is_active: bool | None = None


class PasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    current_password: str = Field(max_length=MAX_PASSWORD_LENGTH)
    new_password: Password


Name = Annotated[str, Field(min_length=1, max_length=60)]


class RegistrationRequest(BaseModel):
    """Demande d'inscription (formulaire multipart, avec photo facultative)."""

    email: NormalizedEmail
    password: Password
    first_name: Name
    last_name: Name
    job_title: str = Field(min_length=1, max_length=120)
    # On ne peut pas demander à être administrateur.
    requested_access_level: Literal[AccessLevel.MEMBER, AccessLevel.MANAGER] = AccessLevel.MEMBER
    skills: Skills = []

    @property
    def full_name(self) -> str:
        return f"{self.first_name.strip()} {self.last_name.strip()}"


class PendingRegistration(UserPublic):
    requested_access_level: AccessLevel | None


class RegistrationApproval(BaseModel):
    model_config = ConfigDict(extra="forbid")

    access_level: AccessLevel
