import logging
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import (
    DUMMY_PASSWORD_HASH,
    create_access_token,
    generate_refresh_token,
    hash_refresh_token,
    verify_password,
)
from app.models import RefreshToken, User
from app.schemas.auth import TokenPair
from app.services.errors import AuthenticationError, PermissionDeniedError, RateLimitedError

logger = logging.getLogger(__name__)

INVALID_CREDENTIALS = "Email ou mot de passe incorrect."
INVALID_REFRESH = "Session expirée, veuillez vous reconnecter."
TOO_MANY_ATTEMPTS = "Trop de tentatives. Réessayez dans quelques minutes."
PENDING_APPROVAL = "Votre compte est en attente de validation par un administrateur."


def _issue_tokens(db: Session, user: User, family_id: uuid.UUID, settings: Settings) -> TokenPair:
    raw_refresh = generate_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            family_id=family_id,
            token_hash=hash_refresh_token(raw_refresh),
            expires_at=datetime.now(UTC) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    db.commit()
    return TokenPair(
        access_token=create_access_token(user.id, settings),
        refresh_token=raw_refresh,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def login(
    db: Session,
    email: str,
    password: str,
    client_key: str,
    limiter: SlidingWindowRateLimiter,
    settings: Settings,
) -> TokenPair:
    rate_key = f"{client_key}:{email}"
    if limiter.is_blocked(rate_key):
        raise RateLimitedError(TOO_MANY_ATTEMPTS)

    user = db.scalar(select(User).where(User.email == email))
    # On vérifie toujours un hash, même si le compte n'existe pas, pour ne pas
    # divulguer l'existence d'un email via le temps de réponse.
    password_ok = verify_password(password, user.password_hash if user else DUMMY_PASSWORD_HASH)
    # Message explicite seulement si le mot de passe est correct : on ne
    # révèle rien à quelqu'un qui ne connaît pas les identifiants.
    if user is not None and password_ok and user.pending_approval:
        raise PermissionDeniedError(PENDING_APPROVAL)
    if user is None or not password_ok or not user.is_active:
        limiter.record_failure(rate_key)
        logger.info("Échec de connexion (client=%s)", client_key)
        raise AuthenticationError(INVALID_CREDENTIALS)

    limiter.reset(rate_key)
    return _issue_tokens(db, user, family_id=uuid.uuid4(), settings=settings)


def _revoke_family(db: Session, family_id: uuid.UUID) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    db.commit()


def refresh(db: Session, raw_refresh: str, settings: Settings) -> TokenPair:
    """Échange un refresh token contre une nouvelle paire (rotation).

    Si un token déjà révoqué est présenté, on suppose qu'il a été volé et on
    révoque toute la famille : le voleur comme l'utilisateur légitime devront
    se reconnecter.
    """
    stored = db.scalar(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_refresh_token(raw_refresh))
        .with_for_update()
    )
    if stored is None:
        raise AuthenticationError(INVALID_REFRESH)

    if stored.revoked_at is not None:
        logger.warning("Réutilisation d'un refresh token révoqué (user=%s)", stored.user_id)
        _revoke_family(db, stored.family_id)
        raise AuthenticationError(INVALID_REFRESH)

    user = db.get(User, stored.user_id)
    if stored.expires_at <= datetime.now(UTC) or user is None or not user.is_active:
        _revoke_family(db, stored.family_id)
        raise AuthenticationError(INVALID_REFRESH)

    stored.revoked_at = datetime.now(UTC)
    return _issue_tokens(db, user, family_id=stored.family_id, settings=settings)


def logout(db: Session, raw_refresh: str) -> None:
    """Révoque la session liée au refresh token. Idempotent."""
    stored = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(raw_refresh))
    )
    if stored is not None:
        _revoke_family(db, stored.family_id)


def revoke_all_sessions(db: Session, user_id: uuid.UUID) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    db.commit()
