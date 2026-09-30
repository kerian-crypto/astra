from pydantic import BaseModel, Field

from app.models.device import MAX_DEVICE_TOKEN_LENGTH
from app.models.enums import DevicePlatform

# Caractères d'un jeton FCM (base64 URL et séparateur « : »).
DEVICE_TOKEN_PATTERN = r"^[A-Za-z0-9_:\-]+$"  # noqa: S105


class DeviceRegister(BaseModel):
    token: str = Field(
        min_length=1, max_length=MAX_DEVICE_TOKEN_LENGTH, pattern=DEVICE_TOKEN_PATTERN
    )
    platform: DevicePlatform


class DeviceUnregister(BaseModel):
    token: str = Field(min_length=1, max_length=MAX_DEVICE_TOKEN_LENGTH)
