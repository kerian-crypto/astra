from fastapi import APIRouter, Request, status

from app.api.deps import AppSettings, CurrentClient, DbSession, LoginLimiter, client_key
from app.schemas.auth import RefreshRequest, TokenPair
from app.schemas.client.auth import (
    ActivationRequest,
    ClientLoginRequest,
    ClientPasswordChange,
    ClientRegisterRequest,
)
from app.services.auth_service import TOO_MANY_ATTEMPTS
from app.services.client import auth as client_auth
from app.services.errors import RateLimitedError, ServiceError

router = APIRouter(prefix="/auth", tags=["client-auth"])


@router.post("/login", response_model=TokenPair)
def login(
    body: ClientLoginRequest,
    request: Request,
    db: DbSession,
    settings: AppSettings,
    limiter: LoginLimiter,
) -> TokenPair:
    return client_auth.login(db, body.email, body.password, client_key(request), limiter, settings)


@router.post("/activate", response_model=TokenPair)
def activate(
    body: ActivationRequest,
    request: Request,
    db: DbSession,
    settings: AppSettings,
    limiter: LoginLimiter,
) -> TokenPair:
    """Activation du compte ou nouveau mot de passe, avec le lien transmis par Astra."""
    key = f"client-activate:{client_key(request)}"
    if limiter.is_blocked(key):
        raise RateLimitedError(TOO_MANY_ATTEMPTS)
    try:
        return client_auth.activate(db, body.token, body.password, settings)
    except ServiceError:
        # Lien invalide : limite les essais de jetons au hasard.
        limiter.record_failure(key)
        raise


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshRequest, db: DbSession, settings: AppSettings) -> TokenPair:
    return client_auth.refresh(db, body.refresh_token, settings)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshRequest, db: DbSession) -> None:
    client_auth.logout(db, body.refresh_token)


@router.post("/password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(body: ClientPasswordChange, account: CurrentClient, db: DbSession) -> None:
    client_auth.change_password(db, account, body.current_password, body.new_password)


@router.post("/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
def register(
    body: ClientRegisterRequest, request: Request, db: DbSession, settings: AppSettings
) -> TokenPair:
    """Inscription libre : nouvelle entreprise (prospect) et session ouverte."""
    limiter = request.app.state.registration_limiter
    return client_auth.register(db, body, client_key(request), limiter, settings)
