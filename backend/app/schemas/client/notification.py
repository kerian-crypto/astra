import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.client_enums import ClientNotificationKind


class ClientNotificationView(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: ClientNotificationKind
    title: str
    body: str | None
    entity_type: str
    entity_id: uuid.UUID
    read_at: datetime | None
    created_at: datetime
