from pydantic import BaseModel, Field

# Texte libre court (motif, référence…) et long (commentaire, description).
ShortText = Field(min_length=1, max_length=200)
LongText = Field(min_length=1, max_length=10_000)


class AttachedFile(BaseModel):
    """Métadonnées d'un fichier joint ; le contenu se télécharge par l'API."""

    name: str
    content_type: str
    size_bytes: int


def attached_file(entity: object) -> AttachedFile | None:
    key = getattr(entity, "file_key", None)
    if not key:
        return None
    return AttachedFile(
        name=entity.file_name or "fichier",  # type: ignore[attr-defined]
        content_type=entity.file_content_type or "application/octet-stream",  # type: ignore[attr-defined]
        size_bytes=entity.file_size or 0,  # type: ignore[attr-defined]
    )
