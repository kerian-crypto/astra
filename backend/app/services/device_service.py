from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import DeviceToken, User
from app.models.enums import DevicePlatform

# Au-delà, les appareils les plus anciens sont oubliés : un compte ne peut
# pas accumuler de jetons sans limite.
MAX_DEVICES_PER_USER = 10


def register(db: Session, user: User, token: str, platform: DevicePlatform) -> None:
    """Associe le jeton au membre connecté (idempotent). Un jeton déjà connu
    (même téléphone, autre compte) change de propriétaire : l'ancien compte
    ne reçoit plus rien sur cet appareil."""
    now = datetime.now(UTC)
    statement = insert(DeviceToken).values(
        user_id=user.id, token=token, platform=platform, created_at=now, updated_at=now
    )
    db.execute(
        statement.on_conflict_do_update(
            index_elements=[DeviceToken.token],
            set_={"user_id": user.id, "platform": platform, "updated_at": now},
        )
    )
    _forget_oldest(db, user)
    db.commit()


def _forget_oldest(db: Session, user: User) -> None:
    keep = (
        select(DeviceToken.id)
        .where(DeviceToken.user_id == user.id)
        .order_by(DeviceToken.updated_at.desc())
        .limit(MAX_DEVICES_PER_USER)
    )
    db.execute(
        delete(DeviceToken).where(DeviceToken.user_id == user.id, DeviceToken.id.not_in(keep))
    )


def unregister(db: Session, user: User, token: str) -> None:
    """Sans effet si le jeton est inconnu ou appartient à un autre compte."""
    db.execute(
        delete(DeviceToken).where(DeviceToken.token == token, DeviceToken.user_id == user.id)
    )
    db.commit()
