"""Inscription en libre-service avec validation par un administrateur.

Le compte est créé inactif (`pending_approval`). Un administrateur l'active en
fixant le niveau d'accès ; la personne ne peut jamais s'attribuer elle-même un
rôle (au mieux, elle en demande un).
"""

import logging
import uuid
from typing import BinaryIO

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.core.storage import FileTooLargeError, LocalFileStorage
from app.models import User
from app.models.enums import AccessLevel, NotificationKind
from app.schemas.user import RegistrationRequest
from app.services import file_types, notification_service
from app.services.errors import NotFoundError, ServiceError

logger = logging.getLogger(__name__)

PHOTO_EXTENSIONS = (".png", ".jpg", ".jpeg")


def store_photo(storage: LocalFileStorage, filename: str, source: BinaryIO, max_bytes: int) -> str:
    """Enregistre une photo PNG/JPEG et renvoie sa clé de stockage."""
    file_type = file_types.resolve(filename)
    if file_type is None or not filename.lower().endswith(PHOTO_EXTENSIONS):
        raise ServiceError("La photo doit être au format PNG ou JPEG.")
    try:
        stored = storage.save(source, max_bytes)
    except FileTooLargeError:
        raise ServiceError(
            f"Photo trop volumineuse (max {max_bytes // (1024 * 1024)} Mo)."
        ) from None
    if not file_types.matches_signature(file_type, stored.head):
        storage.delete(stored.key)
        raise ServiceError("Le fichier n'est pas une image PNG ou JPEG valide.")
    return stored.key


def photo_content_type(storage: LocalFileStorage, key: str) -> str:
    with storage.path(key).open("rb") as file:
        head = file.read(4)
    return "image/png" if head.startswith(b"\x89PNG") else "image/jpeg"


def register(
    db: Session,
    storage: LocalFileStorage,
    data: RegistrationRequest,
    *,
    photo: tuple[str, BinaryIO] | None,
    max_photo_bytes: int,
) -> None:
    """Crée une demande d'inscription. Si l'email existe déjà, rien n'est fait
    mais la réponse est identique : on ne révèle pas qui a un compte."""
    password_hash = hash_password(data.password)
    if db.scalar(select(User.id).where(User.email == data.email)) is not None:
        logger.info("Inscription ignorée : email déjà utilisé")
        return

    photo_key = store_photo(storage, photo[0], photo[1], max_photo_bytes) if photo else None
    user = User(
        email=data.email,
        password_hash=password_hash,
        full_name=data.full_name,
        job_title=data.job_title.strip(),
        skills=data.skills,
        access_level=AccessLevel.MEMBER,
        requested_access_level=data.requested_access_level,
        is_active=False,
        pending_approval=True,
        photo_key=photo_key,
    )
    db.add(user)
    try:
        db.flush()
        admins = db.scalars(
            select(User.id).where(User.access_level == AccessLevel.ADMIN, User.is_active.is_(True))
        )
        for admin_id in admins:
            notification_service.notify(
                db,
                user_id=admin_id,
                actor=None,
                kind=NotificationKind.REGISTRATION_REQUEST,
                title=f"Nouvelle demande d'inscription : {user.full_name}",
                body=f"{user.job_title} · {user.email}",
                entity_type="user",
                entity_id=user.id,
            )
        db.commit()
    except Exception:
        db.rollback()
        if photo_key:
            storage.delete(photo_key)
        raise


def list_pending(db: Session) -> list[User]:
    return list(
        db.scalars(select(User).where(User.pending_approval.is_(True)).order_by(User.created_at))
    )


def _get_pending(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if user is None or not user.pending_approval:
        raise NotFoundError("Demande d'inscription introuvable.")
    return user


def approve(db: Session, user_id: uuid.UUID, access_level: AccessLevel) -> User:
    user = _get_pending(db, user_id)
    user.pending_approval = False
    user.is_active = True
    user.access_level = access_level
    db.commit()
    return user


def reject(db: Session, storage: LocalFileStorage, user_id: uuid.UUID) -> None:
    """Une demande refusée est supprimée : aucune donnée n'y est encore liée."""
    user = _get_pending(db, user_id)
    photo_key = user.photo_key
    db.delete(user)
    db.commit()
    if photo_key:
        storage.delete(photo_key)


def set_photo(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> User:
    new_key = store_photo(storage, filename, source, max_bytes)
    old_key = user.photo_key
    user.photo_key = new_key
    db.commit()
    if old_key:
        storage.delete(old_key)
    return user
