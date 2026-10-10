import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import CurrentClient, DbSession
from app.schemas.client.dashboard import DashboardView
from app.schemas.client.notification import ClientNotificationView
from app.services.client import dashboard, notifications

router = APIRouter(tags=["client-home"])


@router.get("/dashboard", response_model=DashboardView)
def read_dashboard(account: CurrentClient, db: DbSession) -> DashboardView:
    return dashboard.build(db, account)


@router.get("/notifications", response_model=list[ClientNotificationView])
def list_notifications(
    account: CurrentClient,
    db: DbSession,
    unread_only: bool = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[ClientNotificationView]:
    return notifications.list_for_account(
        db, account, unread_only=unread_only, limit=limit, offset=offset
    )


@router.get("/notifications/unread-count")
def unread_count(account: CurrentClient, db: DbSession) -> dict[str, int]:
    return {"count": notifications.unread_count(db, account)}


@router.post("/notifications/{notification_id}/read", response_model=ClientNotificationView)
def mark_read(
    notification_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> ClientNotificationView:
    return notifications.mark_read(db, account, notification_id)


@router.post("/notifications/read-all", status_code=status.HTTP_204_NO_CONTENT)
def mark_all_read(account: CurrentClient, db: DbSession) -> None:
    notifications.mark_all_read(db, account)
