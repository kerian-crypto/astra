"""Texte des documents bureautiques (Word, Excel, PowerPoint, OpenDocument).

Ces formats sont des archives ZIP de XML : on lit directement les parties
utiles avec la bibliothèque standard, sans dépendance supplémentaire. Les
archives sont bornées (taille décompressée, nombre de parties) pour qu'un
fichier piégé (« zip bomb ») ne puisse pas épuiser la mémoire du serveur.
"""

import re
import zipfile
from collections.abc import Callable, Iterator
from pathlib import Path
from xml.etree.ElementTree import Element, XMLParser, fromstring

# Expat (≥ 2.4.1, fourni avec Python 3.13) limite l'expansion d'entités et
# ElementTree ne résout aucune entité externe : pas de « billion laughs » ni XXE.
MAX_PART_BYTES = 20 * 1024 * 1024
MAX_PARTS = 500


class OfficeFileError(Exception):
    """Archive illisible ou hors des limites : document non indexé."""


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _read(archive: zipfile.ZipFile, name: str) -> Element | None:
    try:
        info = archive.getinfo(name)
    except KeyError:
        return None
    if info.file_size > MAX_PART_BYTES:
        raise OfficeFileError(f"Partie trop volumineuse : {name}")
    with archive.open(info) as part:
        data = part.read(MAX_PART_BYTES + 1)
    if len(data) > MAX_PART_BYTES:
        raise OfficeFileError(f"Partie trop volumineuse : {name}")
    return fromstring(data, parser=XMLParser())  # noqa: S314


def _numbered(archive: zipfile.ZipFile, pattern: str) -> list[str]:
    """Parties numérotées (slide2.xml avant slide10.xml)."""
    regex = re.compile(pattern)
    found = [(int(m.group(1)), n) for n in archive.namelist() if (m := regex.fullmatch(n))]
    return [name for _, name in sorted(found)]


def _paragraphs(root: Element, paragraph: str, text: str) -> Iterator[str]:
    """Texte de chaque paragraphe (`w:p` / `a:p`), avec tabulations et sauts de ligne."""
    for node in root.iter():
        if _local(node.tag) != paragraph:
            continue
        parts = []
        for child in node.iter():
            name = _local(child.tag)
            if name == text and child.text:
                parts.append(child.text)
            elif name == "tab":
                parts.append("\t")
            elif name in ("br", "cr"):
                parts.append("\n")
        line = "".join(parts).strip()
        if line:
            yield line


def _docx(archive: zipfile.ZipFile) -> Iterator[str]:
    names = ["word/document.xml"]
    names += _numbered(archive, r"word/header(\d+)\.xml")
    names += _numbered(archive, r"word/footer(\d+)\.xml")
    for name in names:
        if (root := _read(archive, name)) is not None:
            yield from _paragraphs(root, "p", "t")


def _pptx(archive: zipfile.ZipFile) -> Iterator[str]:
    for number, name in enumerate(_numbered(archive, r"ppt/slides/slide(\d+)\.xml"), 1):
        root = _read(archive, name)
        if root is not None:
            yield f"--- Diapositive {number} ---"
            yield from _paragraphs(root, "p", "t")
        notes = _read(archive, f"ppt/notesSlides/notesSlide{number}.xml")
        if notes is not None:
            lines = list(_paragraphs(notes, "p", "t"))
            if lines:
                yield "Notes : " + " ".join(lines)


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    root = _read(archive, "xl/sharedStrings.xml")
    if root is None:
        return []
    return [
        "".join(t.text or "" for t in item.iter() if _local(t.tag) == "t")
        for item in root
        if _local(item.tag) == "si"
    ]


def _sheet_names(archive: zipfile.ZipFile) -> list[str]:
    root = _read(archive, "xl/workbook.xml")
    if root is None:
        return []
    return [n.get("name", "") for n in root.iter() if _local(n.tag) == "sheet"]


def _cell(cell: Element, shared: list[str]) -> str:
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(t.text or "" for t in cell.iter() if _local(t.tag) == "t")
    value = next((v.text or "" for v in cell if _local(v.tag) == "v"), "")
    if kind == "s" and value.isdigit():
        index = int(value)
        return shared[index] if index < len(shared) else ""
    return value


def _xlsx(archive: zipfile.ZipFile) -> Iterator[str]:
    shared = _shared_strings(archive)
    names = _sheet_names(archive)
    for number, part in enumerate(_numbered(archive, r"xl/worksheets/sheet(\d+)\.xml"), 1):
        root = _read(archive, part)
        if root is None:
            continue
        title = names[number - 1] if number <= len(names) else f"Feuille {number}"
        yield f"--- Feuille « {title} » ---"
        for row in root.iter():
            if _local(row.tag) != "row":
                continue
            values = [_cell(c, shared).strip() for c in row if _local(c.tag) == "c"]
            if any(values):
                yield " | ".join(values)


def _odt(archive: zipfile.ZipFile) -> Iterator[str]:
    root = _read(archive, "content.xml")
    if root is None:
        return
    for node in root.iter():
        if _local(node.tag) in ("p", "h"):
            line = "".join(node.itertext()).strip()
            if line:
                yield line


OPENXML = "application/vnd.openxmlformats-officedocument"
# Clé : type MIME retenu par `file_types` pour l'extension.
_EXTRACTORS: dict[str, Callable[[zipfile.ZipFile], Iterator[str]]] = {
    f"{OPENXML}.wordprocessingml.document": _docx,
    f"{OPENXML}.presentationml.presentation": _pptx,
    f"{OPENXML}.spreadsheetml.sheet": _xlsx,
    "application/vnd.oasis.opendocument.text": _odt,
}


def is_supported(content_type: str) -> bool:
    return content_type in _EXTRACTORS


def extract(path: Path, content_type: str, max_chars: int) -> str:
    """Texte du document, tronqué à `max_chars` (lève OfficeFileError ou BadZipFile)."""
    extractor = _EXTRACTORS[content_type]
    with zipfile.ZipFile(path) as archive:
        if len(archive.infolist()) > MAX_PARTS:
            raise OfficeFileError("Archive avec trop de parties.")
        lines: list[str] = []
        size = 0
        for line in extractor(archive):
            lines.append(line)
            size += len(line) + 1
            if size >= max_chars:
                break
    return "\n".join(lines)
