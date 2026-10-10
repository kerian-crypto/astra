import uuid
from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel


class DocumentCategory(StrEnum):
    """Catégories de l'espace documentaire client (§21)."""

    CONTRACT = "contract"
    INVOICE = "invoice"
    SPECIFICATION = "specification"
    DELIVERABLE = "deliverable"
    REPORT = "report"
    ADMINISTRATIVE = "administrative"
    OTHER = "other"


class DocumentSource(StrEnum):
    """Origine du fichier : chaque source a sa propre route de téléchargement."""

    DOCUMENT = "document"
    DELIVERABLE = "deliverable_version"
    CONTRACT = "contract"
    INVOICE = "invoice"


class ClientDocumentView(BaseModel):
    id: uuid.UUID
    source: DocumentSource
    category: DocumentCategory
    title: str
    filename: str
    content_type: str
    size_bytes: int
    version: int
    project_id: uuid.UUID | None
    project_name: str | None
    created_at: datetime
    download_path: str
