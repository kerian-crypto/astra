from pydantic import BaseModel, ConfigDict, Field

from app.schemas.user import MAX_PASSWORD_LENGTH, FullName, NormalizedEmail, Password


class ClientLoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: NormalizedEmail
    password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)


class ActivationRequest(BaseModel):
    """Activation du compte ou nouveau mot de passe, via le lien d'Astra."""

    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=20, max_length=256)
    password: Password


class ClientPasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    current_password: str = Field(max_length=MAX_PASSWORD_LENGTH)
    new_password: Password


class InvitationLink(BaseModel):
    """Renvoyé une seule fois au membre d'Astra qui génère le lien."""

    token: str
    link: str
    purpose: str
    expires_in_hours: int


class ClientRegisterRequest(BaseModel):
    """Inscription libre depuis Astra Client : crée une nouvelle entreprise
    (prospect), jamais l'accès à une entreprise existante."""

    model_config = ConfigDict(extra="forbid")

    company_name: str = Field(min_length=1, max_length=150)
    full_name: FullName
    email: NormalizedEmail
    phone: str | None = Field(default=None, max_length=40)
    country: str | None = Field(default=None, max_length=80)
    password: Password


class AccountDeleteRequest(BaseModel):
    """Suppression de son propre compte : le mot de passe est redemandé."""

    model_config = ConfigDict(extra="forbid")

    password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)
