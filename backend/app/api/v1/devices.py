from fastapi import APIRouter, status

from app.api.deps import CurrentUser, DbSession
from app.schemas.device import DeviceRegister, DeviceUnregister
from app.services import device_service

router = APIRouter(prefix="/devices", tags=["devices"])


@router.put("", status_code=status.HTTP_204_NO_CONTENT)
def register_device(body: DeviceRegister, user: CurrentUser, db: DbSession) -> None:
    """Enregistre le jeton push de l'appareil (idempotent)."""
    device_service.register(db, user, body.token, body.platform)


@router.post("/unregister", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(body: DeviceUnregister, user: CurrentUser, db: DbSession) -> None:
    """À appeler avant la déconnexion : l'appareil ne reçoit plus de push."""
    device_service.unregister(db, user, body.token)
