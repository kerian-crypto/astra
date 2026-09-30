from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import InvalidTokenError, decode_access_token
from app.core.storage import LocalFileStorage
from app.db.session import get_db
from app.models import User
from app.services import permissions

_bearer = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentification requise.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(
    db: DbSession,
    settings: AppSettings,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None:
        raise _unauthorized()
    try:
        user_id = decode_access_token(credentials.credentials, settings)
    except InvalidTokenError:
        raise _unauthorized() from None

    # Vérifié à chaque requête : un membre désactivé perd l'accès immédiatement,
    # sans attendre l'expiration de son access token.
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise _unauthorized()
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_admin(user: CurrentUser) -> User:
    if not permissions.is_admin(user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Réservé aux administrateurs.")
    return user


AdminUser = Annotated[User, Depends(require_admin)]


def get_login_limiter(request: Request) -> SlidingWindowRateLimiter:
    return request.app.state.login_limiter


LoginLimiter = Annotated[SlidingWindowRateLimiter, Depends(get_login_limiter)]


def client_key(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def get_storage(settings: AppSettings) -> LocalFileStorage:
    return LocalFileStorage(settings.UPLOAD_DIR)


Storage = Annotated[LocalFileStorage, Depends(get_storage)]


PHOTO_SUBDIR = "avatars"


def get_photo_storage(settings: AppSettings) -> LocalFileStorage:
    """Photos des membres et des canaux (PNG/JPEG uniquement)."""
    return LocalFileStorage(f"{settings.UPLOAD_DIR}/{PHOTO_SUBDIR}")


PhotoStorage = Annotated[LocalFileStorage, Depends(get_photo_storage)]


def require_upload_quota(request: Request, user: CurrentUser) -> None:
    """Compte chaque envoi de fichier du membre ; au-delà du quota : 429."""
    limiter: SlidingWindowRateLimiter = request.app.state.upload_limiter
    key = str(user.id)
    if limiter.is_blocked(key):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "Trop d'envois de fichiers. Réessayez plus tard."
        )
    limiter.record_failure(key)


UploadQuota = Depends(require_upload_quota)
