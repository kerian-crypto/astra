from fastapi import APIRouter, status
from fastapi.responses import FileResponse

from app.api.deps import CurrentClient, DbSession, PhotoStorage
from app.schemas.client.company import (
    CompanyClientUpdate,
    CompanyUserView,
    CompanyView,
    MeUpdate,
    MeView,
)
from app.schemas.device import DeviceRegister, DeviceUnregister
from app.services.client import accounts, dashboard, devices
from app.services.errors import NotFoundError
from app.services.registration_service import photo_content_type

router = APIRouter(tags=["client-profile"])


def me_view(account) -> MeView:
    return MeView.model_validate(
        {
            **MeView.model_validate(account).model_dump(exclude={"company"}),
            "company": dashboard.company_view(account),
        }
    )


@router.get("/me", response_model=MeView)
def read_me(account: CurrentClient) -> MeView:
    return me_view(account)


@router.patch("/me", response_model=MeView)
def update_me(body: MeUpdate, account: CurrentClient, db: DbSession) -> MeView:
    return me_view(accounts.update_me(db, account, body))


@router.get("/company", response_model=CompanyView)
def read_company(account: CurrentClient) -> CompanyView:
    return dashboard.company_view(account)


@router.patch("/company", response_model=CompanyView)
def update_company(body: CompanyClientUpdate, account: CurrentClient, db: DbSession) -> CompanyView:
    accounts.update_own_company(db, account, body)
    return dashboard.company_view(account)


@router.get("/company/logo", response_class=FileResponse)
def company_logo(account: CurrentClient, storage: PhotoStorage) -> FileResponse:
    key = account.company.logo_key
    if not key:
        raise NotFoundError("Aucun logo.")
    return FileResponse(
        storage.path(key),
        media_type=photo_content_type(storage, key),
        headers={"Cache-Control": "private, max-age=3600", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/company/users", response_model=list[CompanyUserView])
def company_users(account: CurrentClient, db: DbSession) -> list[CompanyUserView]:
    return [
        CompanyUserView.model_validate(
            {
                **CompanyUserView.model_validate(colleague).model_dump(),
                "is_activated": colleague.activated_at is not None,
            }
        )
        for colleague in accounts.list_colleagues(db, account)
    ]


@router.put("/devices", status_code=status.HTTP_204_NO_CONTENT)
def register_device(body: DeviceRegister, account: CurrentClient, db: DbSession) -> None:
    devices.register(db, account, body.token, body.platform)


@router.post("/devices/unregister", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(body: DeviceUnregister, account: CurrentClient, db: DbSession) -> None:
    devices.unregister(db, account, body.token)
