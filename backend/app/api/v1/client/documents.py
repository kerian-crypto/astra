import uuid

from fastapi import APIRouter
from fastapi.responses import FileResponse

from app.api.deps import CurrentClient, DbSession, Storage
from app.api.files import attachment_response
from app.schemas.client.document import ClientDocumentView, DocumentCategory
from app.services.client import documents

router = APIRouter(tags=["client-documents"])


@router.get("/documents", response_model=list[ClientDocumentView])
def list_documents(
    account: CurrentClient,
    db: DbSession,
    category: DocumentCategory | None = None,
    project_id: uuid.UUID | None = None,
) -> list[ClientDocumentView]:
    return documents.list_documents(db, account, category=category, project_id=project_id)


@router.get("/documents/{document_id}/versions", response_model=list[ClientDocumentView])
def document_versions(
    document_id: uuid.UUID, account: CurrentClient, db: DbSession
) -> list[ClientDocumentView]:
    document = documents.get_shared_document(db, account, document_id)
    return documents.versions(db, account, document)


@router.get("/documents/{document_id}/download", response_class=FileResponse)
def download_document(
    document_id: uuid.UUID, account: CurrentClient, db: DbSession, storage: Storage
) -> FileResponse:
    document = documents.get_shared_document(db, account, document_id)
    documents.record_download(
        db,
        account,
        entity_type="document",
        entity_id=document.id,
        title=document.title,
        project_id=document.project_id,
    )
    return attachment_response(
        storage, document.storage_key, document.filename, document.content_type
    )
