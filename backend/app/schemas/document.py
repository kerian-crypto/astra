import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import DocumentKind
from app.schemas.user import UserPublic

DocumentTitle = Field(min_length=1, max_length=200)


class DocumentPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    project_id: uuid.UUID | None
    title: str
    kind: DocumentKind
    filename: str
    content_type: str
    size_bytes: int
    uploaded_by: UserPublic | None
    created_at: datetime
    is_indexed: bool = False
