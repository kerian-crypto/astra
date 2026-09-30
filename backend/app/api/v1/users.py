import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import AdminUser, CurrentUser, DbSession
from app.schemas.user import (
    PasswordChange,
    UserAdminUpdate,
    UserCreate,
    UserPublic,
    UserSelfUpdate,
)
from app.services import permissions, user_service

router = APIRouter(prefix="/users", tags=["users"])

PageLimit = Annotated[int, Query(ge=1, le=100)]
PageOffset = Annotated[int, Query(ge=0)]


@router.get("/me", response_model=UserPublic)
def read_me(user: CurrentUser) -> UserPublic:
    return user


@router.patch("/me", response_model=UserPublic)
def update_me(body: UserSelfUpdate, user: CurrentUser, db: DbSession) -> UserPublic:
    return user_service.update_self(db, user, body)


@router.post("/me/password", status_code=status.HTTP_204_NO_CONTENT)
def change_my_password(body: PasswordChange, user: CurrentUser, db: DbSession) -> None:
    user_service.change_password(db, user, body)


@router.get("", response_model=list[UserPublic])
def list_users(
    user: CurrentUser,
    db: DbSession,
    include_inactive: bool = False,
    limit: PageLimit = 50,
    offset: PageOffset = 0,
) -> list[UserPublic]:
    # Seuls les admins voient les comptes désactivés.
    return user_service.list_users(
        db,
        include_inactive=include_inactive and permissions.is_admin(user),
        limit=limit,
        offset=offset,
    )


@router.post("", response_model=UserPublic, status_code=status.HTTP_201_CREATED)
def create_user(body: UserCreate, _: AdminUser, db: DbSession) -> UserPublic:
    return user_service.create_user(db, body)


@router.get("/{user_id}", response_model=UserPublic)
def read_user(user_id: uuid.UUID, _: CurrentUser, db: DbSession) -> UserPublic:
    return user_service.get_user(db, user_id)


@router.patch("/{user_id}", response_model=UserPublic)
def update_user(
    user_id: uuid.UUID, body: UserAdminUpdate, _: AdminUser, db: DbSession
) -> UserPublic:
    return user_service.update_by_admin(db, user_service.get_user(db, user_id), body)
