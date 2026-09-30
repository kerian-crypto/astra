import uuid
from typing import Annotated

from fastapi import APIRouter, File, Form, Request, UploadFile, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse
from pydantic import BaseModel, ValidationError

from app.api.deps import (
    AdminUser,
    AppSettings,
    CurrentUser,
    DbSession,
    PhotoStorage,
    UploadQuota,
    client_key,
)
from app.models import User
from app.schemas.user import (
    PendingRegistration,
    RegistrationApproval,
    RegistrationRequest,
    UserPublic,
)
from app.services import registration_service
from app.services.errors import NotFoundError, RateLimitedError

router = APIRouter(tags=["registration"])


class RegistrationAccepted(BaseModel):
    detail: str


@router.post(
    "/auth/register",
    response_model=RegistrationAccepted,
    status_code=status.HTTP_202_ACCEPTED,
)
def register(
    request: Request,
    db: DbSession,
    storage: PhotoStorage,
    settings: AppSettings,
    email: Annotated[str, Form()],
    password: Annotated[str, Form()],
    first_name: Annotated[str, Form()],
    last_name: Annotated[str, Form()],
    job_title: Annotated[str, Form()],
    requested_access_level: Annotated[str, Form()] = "member",
    skills: Annotated[list[str] | None, Form()] = None,
    photo: Annotated[UploadFile | None, File()] = None,
) -> RegistrationAccepted:
    """Demande d'inscription (multipart, photo facultative). Réponse identique
    que l'email existe ou non."""
    limiter = request.app.state.registration_limiter
    key = client_key(request)
    if limiter.is_blocked(key):
        raise RateLimitedError("Trop de demandes d'inscription. Réessayez plus tard.")
    limiter.record_failure(key)  # chaque demande compte
    try:
        data = RegistrationRequest(
            email=email,
            password=password,
            first_name=first_name,
            last_name=last_name,
            job_title=job_title,
            requested_access_level=requested_access_level,
            skills=skills or [],
        )
    except ValidationError as exc:
        raise RequestValidationError(exc.errors(include_url=False)) from None
    registration_service.register(
        db,
        storage,
        data,
        photo=(photo.filename or "photo", photo.file) if photo else None,
        max_photo_bytes=settings.MAX_PHOTO_BYTES,
    )
    return RegistrationAccepted(
        detail="Demande envoyée. Un administrateur doit valider votre compte."
    )


@router.get("/users/pending", response_model=list[PendingRegistration])
def list_pending(_: AdminUser, db: DbSession) -> list[User]:
    return registration_service.list_pending(db)


@router.post("/users/{user_id}/approve", response_model=UserPublic)
def approve(user_id: uuid.UUID, body: RegistrationApproval, _: AdminUser, db: DbSession) -> User:
    return registration_service.approve(db, user_id, body.access_level)


@router.post("/users/{user_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
def reject(user_id: uuid.UUID, _: AdminUser, db: DbSession, storage: PhotoStorage) -> None:
    registration_service.reject(db, storage, user_id)


@router.put("/users/me/photo", response_model=UserPublic, dependencies=[UploadQuota])
def update_my_photo(
    photo: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: PhotoStorage,
    settings: AppSettings,
) -> User:
    return registration_service.set_photo(
        db, storage, user, photo.filename or "photo", photo.file, settings.MAX_PHOTO_BYTES
    )


@router.get("/users/{user_id}/photo", response_class=FileResponse)
def read_photo(
    user_id: uuid.UUID, _: CurrentUser, db: DbSession, storage: PhotoStorage
) -> FileResponse:
    """Photos visibles des seuls membres connectés (pas d'URL publique)."""
    user = db.get(User, user_id)
    if user is None or not user.photo_key:
        raise NotFoundError("Photo introuvable.")
    return FileResponse(
        storage.path(user.photo_key),
        media_type=registration_service.photo_content_type(storage, user.photo_key),
        headers={
            "X-Content-Type-Options": "nosniff",
            # URL versionnée : la photo peut être mise en cache côté client.
            "Cache-Control": "private, max-age=86400",
        },
    )
