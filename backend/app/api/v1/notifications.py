import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.notification import NotificationPublic
from app.services import notification_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationPublic])
def list_notifications(
    user: CurrentUser,
    db: DbSession,
    unread_only: bool = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[NotificationPublic]:
    return notification_service.list_for_user(
        db, user, unread_only=unread_only, limit=limit, offset=offset
    )


@router.post("/{notification_id}/read", response_model=NotificationPublic)
def mark_read(notification_id: uuid.UUID, user: CurrentUser, db: DbSession) -> NotificationPublic:
    return notification_service.mark_read(db, user, notification_id)


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
def mark_all_read(user: CurrentUser, db: DbSession) -> None:
    notification_service.mark_all_read(db, user)
