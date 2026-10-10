from urllib.parse import quote

from fastapi.responses import FileResponse

from app.core.storage import LocalFileStorage
from app.models.attachment import AttachedFileMixin
from app.services.client.files import require_file


def attachment_response(
    storage: LocalFileStorage, key: str, filename: str, content_type: str
) -> FileResponse:
    """Toujours en pièce jointe, jamais mis en cache : le navigateur
    n'interprète pas le contenu."""
    return FileResponse(
        storage.path(key),
        media_type=content_type,
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename)}",
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, no-store",
        },
    )


def attached_file_response(storage: LocalFileStorage, entity: AttachedFileMixin) -> FileResponse:
    return attachment_response(
        storage,
        require_file(entity),
        entity.file_name or "fichier",
        entity.file_content_type or "application/octet-stream",
    )
