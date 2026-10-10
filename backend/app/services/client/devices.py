"""Jetons push des appareils Astra Client (mêmes règles que les membres)."""

from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import ClientAccount, ClientDeviceToken
from app.models.enums import DevicePlatform
from app.services.device_service import MAX_DEVICES_PER_USER


def register(db: Session, account: ClientAccount, token: str, platform: DevicePlatform) -> None:
    now = datetime.now(UTC)
    statement = insert(ClientDeviceToken).values(
        account_id=account.id, token=token, platform=platform, created_at=now, updated_at=now
    )
    db.execute(
        statement.on_conflict_do_update(
            index_elements=[ClientDeviceToken.token],
            set_={"account_id": account.id, "platform": platform, "updated_at": now},
        )
    )
    keep = (
        select(ClientDeviceToken.id)
        .where(ClientDeviceToken.account_id == account.id)
        .order_by(ClientDeviceToken.updated_at.desc())
        .limit(MAX_DEVICES_PER_USER)
    )
    db.execute(
        delete(ClientDeviceToken).where(
            ClientDeviceToken.account_id == account.id, ClientDeviceToken.id.not_in(keep)
        )
    )
    db.commit()


def unregister(db: Session, account: ClientAccount, token: str) -> None:
    db.execute(
        delete(ClientDeviceToken).where(
            ClientDeviceToken.token == token, ClientDeviceToken.account_id == account.id
        )
    )
    db.commit()
