from fastapi import APIRouter, Request, status

from app.api.deps import AppSettings, DbSession, LoginLimiter, client_key
from app.schemas.auth import LoginRequest, RefreshRequest, TokenPair
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenPair)
def login(
    body: LoginRequest,
    request: Request,
    db: DbSession,
    settings: AppSettings,
    limiter: LoginLimiter,
) -> TokenPair:
    return auth_service.login(db, body.email, body.password, client_key(request), limiter, settings)


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshRequest, db: DbSession, settings: AppSettings) -> TokenPair:
    return auth_service.refresh(db, body.refresh_token, settings)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshRequest, db: DbSession) -> None:
    auth_service.logout(db, body.refresh_token)
