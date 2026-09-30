"""Formats de fichiers acceptés.

Le type MIME est déduit de l'extension (pas de l'en-tête envoyé par le
client) puis confirmé par la signature du contenu quand elle existe.
"""

import logging
from dataclasses import dataclass
from pathlib import Path

from app.models.enums import AttachmentKind

logger = logging.getLogger(__name__)

MAX_EXTRACTED_CHARS = 500_000
# Borne le coût d'extraction d'un PDF malveillant ou démesuré (au-delà : non indexé).
MAX_PDF_PAGES = 300
ZIP_MAGIC = b"PK\x03\x04"


@dataclass(frozen=True)
class FileType:
    content_type: str
    magic: tuple[bytes, ...] = ()  # vide = texte, pas de signature
    is_text: bool = False
    magic_offset: int = 0  # ex. conteneurs MP4 : « ftyp » à l'octet 4


FILE_TYPES: dict[str, FileType] = {
    ".pdf": FileType("application/pdf", (b"%PDF",)),
    ".txt": FileType("text/plain; charset=utf-8", is_text=True),
    ".md": FileType("text/markdown; charset=utf-8", is_text=True),
    ".csv": FileType("text/csv; charset=utf-8", is_text=True),
    ".png": FileType("image/png", (b"\x89PNG",)),
    ".jpg": FileType("image/jpeg", (b"\xff\xd8\xff",)),
    ".jpeg": FileType("image/jpeg", (b"\xff\xd8\xff",)),
    ".docx": FileType(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document", (ZIP_MAGIC,)
    ),
    ".xlsx": FileType(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", (ZIP_MAGIC,)
    ),
    ".pptx": FileType(
        "application/vnd.openxmlformats-officedocument.presentationml.presentation", (ZIP_MAGIC,)
    ),
    ".odt": FileType("application/vnd.oasis.opendocument.text", (ZIP_MAGIC,)),
}


def resolve(filename: str) -> FileType | None:
    return FILE_TYPES.get(Path(filename).suffix.lower())


FTYP = (b"ftyp",)
MP3_MAGIC = (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2")

# Médias acceptés dans le chat, en plus des documents. Aucun format interprété
# par un navigateur (HTML, SVG…) : les médias peuvent être servis « inline ».
MEDIA_TYPES: dict[str, tuple[FileType, AttachmentKind]] = {
    ".png": (FILE_TYPES[".png"], AttachmentKind.IMAGE),
    ".jpg": (FILE_TYPES[".jpg"], AttachmentKind.IMAGE),
    ".jpeg": (FILE_TYPES[".jpeg"], AttachmentKind.IMAGE),
    ".gif": (FileType("image/gif", (b"GIF87a", b"GIF89a")), AttachmentKind.IMAGE),
    ".webp": (FileType("image/webp", (b"RIFF",)), AttachmentKind.IMAGE),
    ".heic": (FileType("image/heic", FTYP, magic_offset=4), AttachmentKind.IMAGE),
    ".mp4": (FileType("video/mp4", FTYP, magic_offset=4), AttachmentKind.VIDEO),
    ".mov": (FileType("video/quicktime", FTYP, magic_offset=4), AttachmentKind.VIDEO),
    ".3gp": (FileType("video/3gpp", FTYP, magic_offset=4), AttachmentKind.VIDEO),
    ".webm": (FileType("video/webm", (b"\x1a\x45\xdf\xa3",)), AttachmentKind.VIDEO),
    ".m4a": (FileType("audio/mp4", FTYP, magic_offset=4), AttachmentKind.AUDIO),
    ".aac": (FileType("audio/aac", (b"\xff\xf1", b"\xff\xf9")), AttachmentKind.AUDIO),
    ".mp3": (FileType("audio/mpeg", MP3_MAGIC), AttachmentKind.AUDIO),
    ".ogg": (FileType("audio/ogg", (b"OggS",)), AttachmentKind.AUDIO),
    ".opus": (FileType("audio/ogg", (b"OggS",)), AttachmentKind.AUDIO),
    ".wav": (FileType("audio/wav", (b"RIFF",)), AttachmentKind.AUDIO),
}


def resolve_attachment(filename: str) -> tuple[FileType, AttachmentKind] | None:
    """Type d'une pièce jointe du chat : média, sinon document classique."""
    suffix = Path(filename).suffix.lower()
    if suffix in MEDIA_TYPES:
        return MEDIA_TYPES[suffix]
    document = FILE_TYPES.get(suffix)
    return (document, AttachmentKind.FILE) if document else None


def matches_signature(file_type: FileType, head: bytes) -> bool:
    if file_type.is_text:
        return b"\x00" not in head
    content = head[file_type.magic_offset :]
    return any(content.startswith(magic) for magic in file_type.magic)


def extract_text(file_type: FileType, path: Path) -> str | None:
    """Texte indexé pour la recherche et l'IA. Échec d'extraction = document
    conservé mais non indexé (journalisé)."""
    try:
        if file_type.is_text:
            text = path.read_text(encoding="utf-8", errors="replace")
        elif file_type.content_type == "application/pdf":
            from pypdf import PdfReader

            reader = PdfReader(path)
            if len(reader.pages) > MAX_PDF_PAGES:
                logger.info("PDF de %s pages non indexé : %s", len(reader.pages), path.name)
                return None
            parts: list[str] = []
            size = 0
            for page in reader.pages:
                parts.append(page.extract_text() or "")
                size += len(parts[-1])
                if size >= MAX_EXTRACTED_CHARS:
                    break
            text = "\n".join(parts)
        else:
            return None
    except Exception:
        logger.warning("Extraction de texte impossible pour %s", path.name, exc_info=True)
        return None
    text = text.replace("\x00", "").strip()
    return text[:MAX_EXTRACTED_CHARS] or None
