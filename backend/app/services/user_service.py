import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import hash_password, verify_password
from app.models import User
from app.models.enums import AccessLevel
from app.schemas.user import PasswordChange, UserAdminUpdate, UserCreate, UserSelfUpdate
from app.services import auth_service
from app.services.errors import AuthenticationError, ConflictError, NotFoundError

EMAIL_TAKEN = "Un membre utilise déjà cet email."
LAST_ADMIN = "Impossible de retirer le dernier administrateur actif."


def create_user(db: Session, data: UserCreate) -> User:
    user = User(
        email=data.email,
        password_hash=hash_password(data.password),
        full_name=data.full_name,
        job_title=data.job_title,
        access_level=data.access_level,
        skills=data.skills,
        availability=data.availability,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError(EMAIL_TAKEN) from exc
    return user


def list_users(db: Session, *, include_inactive: bool, limit: int, offset: int) -> list[User]:
    statement = (
        select(User)
        .where(User.pending_approval.is_(False))
        .order_by(User.full_name)
        .limit(limit)
        .offset(offset)
    )
    if not include_inactive:
        statement = statement.where(User.is_active.is_(True))
    return list(db.scalars(statement))


def get_user(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise NotFoundError("Membre introuvable.")
    return user


def _count_active_admins(db: Session) -> int:
    """Verrouille les lignes des admins actifs jusqu'au commit : deux
    rétrogradations simultanées ne peuvent pas passer toutes les deux."""
    locked = db.scalars(
        select(User.id)
        .where(User.access_level == AccessLevel.ADMIN, User.is_active.is_(True))
        .with_for_update()
    )
    return len(list(locked))


def _apply_changes(user: User, changes: dict) -> None:
    for field, value in changes.items():
        setattr(user, field, value)


def update_self(db: Session, user: User, data: UserSelfUpdate) -> User:
    _apply_changes(user, data.model_dump(exclude_unset=True))
    db.commit()
    return user


def update_by_admin(db: Session, user: User, data: UserAdminUpdate) -> User:
    changes = data.model_dump(exclude_unset=True)
    loses_admin = (
        changes.get("access_level", user.access_level) != AccessLevel.ADMIN
        or changes.get("is_active", user.is_active) is False
    )
    is_active_admin = user.access_level == AccessLevel.ADMIN and user.is_active
    if is_active_admin and loses_admin and _count_active_admins(db) <= 1:
        raise ConflictError(LAST_ADMIN)

    _apply_changes(user, changes)
    db.commit()
    if changes.get("is_active") is False:
        auth_service.revoke_all_sessions(db, user.id)
    return user


def change_password(db: Session, user: User, data: PasswordChange) -> None:
    if not verify_password(data.current_password, user.password_hash):
        raise AuthenticationError("Mot de passe actuel incorrect.")
    user.password_hash = hash_password(data.new_password)
    db.commit()
    # Un changement de mot de passe déconnecte toutes les autres sessions.
    auth_service.revoke_all_sessions(db, user.id)
