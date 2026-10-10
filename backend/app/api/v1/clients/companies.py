import uuid
from typing import Annotated

from fastapi import APIRouter, File, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, CurrentUser, DbSession, PhotoStorage, UploadQuota
from app.schemas.client.auth import InvitationLink
from app.schemas.client.company import (
    AccountCreate,
    AccountCreated,
    AccountHub,
    AccountUpdate,
    CompanyCreate,
    CompanyHub,
    CompanyUpdate,
)
from app.services.client import accounts
from app.services.errors import NotFoundError
from app.services.registration_service import photo_content_type

router = APIRouter(prefix="/clients", tags=["clients"])


@router.get("/companies", response_model=list[CompanyHub])
def list_companies(
    user: CurrentUser, db: DbSession, include_inactive: bool = False
) -> list[CompanyHub]:
    return [
        accounts.to_hub(db, c)
        for c in accounts.list_companies(db, user, include_inactive=include_inactive)
    ]


@router.post("/companies", response_model=CompanyHub, status_code=status.HTTP_201_CREATED)
def create_company(body: CompanyCreate, user: CurrentUser, db: DbSession) -> CompanyHub:
    return accounts.to_hub(db, accounts.create_company(db, user, body))


@router.get("/companies/{company_id}", response_model=CompanyHub)
def read_company(company_id: uuid.UUID, user: CurrentUser, db: DbSession) -> CompanyHub:
    return accounts.to_hub(db, accounts.get_company(db, user, company_id))


@router.patch("/companies/{company_id}", response_model=CompanyHub)
def update_company(
    company_id: uuid.UUID, body: CompanyUpdate, user: CurrentUser, db: DbSession
) -> CompanyHub:
    company = accounts.get_company(db, user, company_id)
    return accounts.to_hub(db, accounts.update_company(db, user, company, body))


@router.put("/companies/{company_id}/logo", response_model=CompanyHub, dependencies=[UploadQuota])
def set_logo(
    company_id: uuid.UUID,
    file: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: PhotoStorage,
    settings: AppSettings,
) -> CompanyHub:
    company = accounts.get_company(db, user, company_id)
    accounts.set_logo(
        db, storage, company, file.filename or "logo.png", file.file, settings.MAX_PHOTO_BYTES
    )
    return accounts.to_hub(db, company)


@router.get("/companies/{company_id}/logo", response_class=FileResponse)
def read_logo(
    company_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: PhotoStorage
) -> FileResponse:
    company = accounts.get_company(db, user, company_id)
    if not company.logo_key:
        raise NotFoundError("Aucun logo.")
    return FileResponse(
        storage.path(company.logo_key),
        media_type=photo_content_type(storage, company.logo_key),
        headers={"Cache-Control": "private, max-age=3600", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/companies/{company_id}/accounts", response_model=list[AccountHub])
def list_accounts(company_id: uuid.UUID, user: CurrentUser, db: DbSession) -> list[AccountHub]:
    return accounts.list_accounts(db, accounts.get_company(db, user, company_id))


@router.post(
    "/companies/{company_id}/accounts",
    response_model=AccountCreated,
    status_code=status.HTTP_201_CREATED,
)
def create_account(
    company_id: uuid.UUID,
    body: AccountCreate,
    user: CurrentUser,
    db: DbSession,
    settings: AppSettings,
) -> AccountCreated:
    """Crée le compte et renvoie (une seule fois) le lien d'activation à transmettre."""
    company = accounts.get_company(db, user, company_id)
    account, invitation = accounts.create_account(db, user, company, body, settings)
    return AccountCreated(account=AccountHub.model_validate(account), invitation=invitation)


@router.patch("/accounts/{account_id}", response_model=AccountHub)
def update_account(
    account_id: uuid.UUID, body: AccountUpdate, user: CurrentUser, db: DbSession
) -> AccountHub:
    account = accounts.get_account(db, user, account_id)
    return accounts.update_account(db, user, account, body)


@router.post("/accounts/{account_id}/invitation", response_model=InvitationLink)
def reissue_invitation(
    account_id: uuid.UUID, user: CurrentUser, db: DbSession, settings: AppSettings
) -> InvitationLink:
    """Nouveau lien : activation, ou nouveau mot de passe si le compte est déjà actif."""
    account = accounts.get_account(db, user, account_id)
    return accounts.reissue_invitation(db, user, account, settings)
