"""Fichiers joints du domaine client : même stockage et mêmes contrôles que
les documents (nom généré, extension autorisée, signature vérifiée)."""

from typing import BinaryIO

from app.core.storage import FileTooLargeError, LocalFileStorage
from app.models.attachment import AttachedFileMixin
from app.services import file_types
from app.services.document_service import safe_filename
from app.services.errors import ServiceError


def attach(
    storage: LocalFileStorage,
    target: AttachedFileMixin,
    *,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
    allow_media: bool = False,
) -> str:
    """Enregistre le fichier et le rattache à `target` (sans commit).
    Renvoie la clé de stockage, à supprimer si la transaction échoue."""
    if allow_media:
        resolved = file_types.resolve_attachment(filename)
        file_type = resolved[0] if resolved else None
    else:
        file_type = file_types.resolve(filename)
    if file_type is None:
        raise ServiceError("Format de fichier non accepté.")
    try:
        stored = storage.save(source, max_bytes)
    except FileTooLargeError:
        raise ServiceError(
            f"Fichier trop volumineux (max {max_bytes // (1024 * 1024)} Mo)."
        ) from None
    if stored.size_bytes == 0 or not file_types.matches_signature(file_type, stored.head):
        storage.delete(stored.key)
        raise ServiceError("Le contenu du fichier ne correspond pas à son extension.")
    target.file_key = stored.key
    target.file_name = safe_filename(filename)
    target.file_content_type = file_type.content_type
    target.file_size = stored.size_bytes
    return stored.key


def require_file(target: AttachedFileMixin) -> str:
    if not target.file_key:
        raise ServiceError("Aucun fichier joint.")
    return target.file_key
