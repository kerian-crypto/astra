import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from pwdlib import PasswordHash

from app.core.config import Settings

# Identifiants de claims JWT, pas des secrets.
ACCESS_TOKEN_TYPE = "access"  # noqa: S105
TOKEN_ISSUER = "astra-hub-api"  # noqa: S105
TOKEN_AUDIENCE = "astra-hub-mobile"  # noqa: S105
REFRESH_TOKEN_BYTES = 48

_password_hash = PasswordHash.recommended()

# Hash factice utilisé quand l'email est inconnu, pour que le temps de réponse
# du login ne révèle pas l'existence d'un compte.
DUMMY_PASSWORD_HASH = _password_hash.hash("astra-hub-timing-equalizer")


class InvalidTokenError(Exception):
    pass


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_hash.verify(password, password_hash)


def create_access_token(user_id: uuid.UUID, settings: Settings) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "type": ACCESS_TOKEN_TYPE,
        "iss": TOKEN_ISSUER,
        "aud": TOKEN_AUDIENCE,
        "iat": now,
        "exp": now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str, settings: Settings) -> uuid.UUID:
    return decode_access_token_with_expiry(token, settings)[0]


def decode_access_token_with_expiry(token: str, settings: Settings) -> tuple[uuid.UUID, datetime]:
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            issuer=TOKEN_ISSUER,
            audience=TOKEN_AUDIENCE,
            options={"require": ["sub", "exp", "iat", "iss", "aud", "type"]},
        )
    except jwt.PyJWTError as exc:
        raise InvalidTokenError from exc

    if payload.get("type") != ACCESS_TOKEN_TYPE:
        raise InvalidTokenError
    try:
        return uuid.UUID(payload["sub"]), datetime.fromtimestamp(payload["exp"], UTC)
    except ValueError as exc:
        raise InvalidTokenError from exc


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def hash_refresh_token(token: str) -> str:
    """Les refresh tokens sont opaques et stockés hachés : une fuite de la base
    ne permet pas de les réutiliser."""
    return hashlib.sha256(token.encode()).hexdigest()
