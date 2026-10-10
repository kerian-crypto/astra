"""Word, Excel, PowerPoint et OpenDocument : texte indexé pour la recherche et Ronda."""

import io
import zipfile

import pytest

from app.services import office_text
from tests.test_documents import project_docs, upload

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
S = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
ODF = (
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'
)


def archive(parts: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in parts.items():
            zf.writestr(name, content)
    return buffer.getvalue()


DOCX = archive(
    {
        "word/document.xml": f"<w:document {W}><w:body>"
        "<w:p><w:r><w:t>Cahier des charges</w:t></w:r></w:p>"
        "<w:p><w:r><w:t>Livraison </w:t></w:r><w:r><w:t>le 15 décembre</w:t></w:r></w:p>"
        "</w:body></w:document>",
        "word/footer1.xml": f"<w:ftr {W}><w:p><w:r><w:t>Confidentiel</w:t></w:r></w:p></w:ftr>",
    }
)
PPTX = archive(
    {
        "ppt/slides/slide10.xml": f"<sld {A}><a:p><a:r><a:t>Fin</a:t></a:r></a:p></sld>",
        "ppt/slides/slide2.xml": f"<sld {A}><a:p><a:r><a:t>Budget</a:t></a:r></a:p></sld>",
        "ppt/notesSlides/notesSlide1.xml": f"<n {A}><a:p><a:r><a:t>À dire</a:t></a:r></a:p></n>",
    }
)
XLSX = archive(
    {
        "xl/workbook.xml": f'<workbook {S}><sheets><sheet name="Budget"/></sheets></workbook>',
        "xl/sharedStrings.xml": f"<sst {S}><si><t>Serveurs</t></si></sst>",
        "xl/worksheets/sheet1.xml": f'<worksheet {S}><sheetData><row><c t="s"><v>0</v></c>'
        '<c><v>1200</v></c><c t="inlineStr"><is><t>mensuel</t></is></c></row>'
        "</sheetData></worksheet>",
    }
)
ODT = archive(
    {
        "content.xml": f"<office:document-content {ODF}><office:body><office:text>"
        "<text:h>Compte rendu</text:h><text:p>Décision : <text:span>Flutter</text:span></text:p>"
        "</office:text></office:body></office:document-content>"
    }
)


@pytest.mark.parametrize(
    ("filename", "content", "expected"),
    [
        ("cdc.docx", DOCX, "Cahier des charges\nLivraison le 15 décembre\nConfidentiel"),
        (
            "revue.pptx",
            PPTX,
            "--- Diapositive 1 ---\nBudget\nNotes : À dire\n--- Diapositive 2 ---\nFin",
        ),
        ("budget.xlsx", XLSX, "--- Feuille « Budget » ---\nServeurs | 1200 | mensuel"),
        ("cr.odt", ODT, "Compte rendu\nDécision : Flutter"),
    ],
)
def test_office_documents_are_indexed(client, team, db, filename, content, expected):
    from app.models import Document

    response = upload(client, team["h"]["lead"], project_docs(team), filename, content)

    assert response.status_code == 201, response.text
    assert response.json()["is_indexed"] is True
    assert db.get(Document, response.json()["id"]).text_content == expected


def test_office_text_is_searchable(client, team):
    upload(client, team["h"]["lead"], project_docs(team), "cdc.docx", DOCX)

    hits = client.get(
        "/api/v1/search", headers=team["h"]["viewer"], params={"q": "livraison"}
    ).json()

    assert [h["title"] for h in hits] == ["Spécifications"]


def test_corrupted_archive_is_kept_but_not_indexed(client, team):
    response = upload(
        client, team["h"]["lead"], project_docs(team), "casse.docx", b"PK\x03\x04garbage"
    )

    assert response.status_code == 201
    assert response.json()["is_indexed"] is False


def test_oversized_part_is_refused(tmp_path, monkeypatch):
    monkeypatch.setattr(office_text, "MAX_PART_BYTES", 100)
    path = tmp_path / "bombe.docx"
    path.write_bytes(archive({"word/document.xml": f"<w:document {W}>{'a' * 1000}</w:document>"}))

    with pytest.raises(office_text.OfficeFileError):
        office_text.extract(path, f"{office_text.OPENXML}.wordprocessingml.document", 1000)


def test_extraction_stops_at_the_character_limit(tmp_path):
    paragraphs = "".join(f"<w:p><w:r><w:t>Ligne {i}</w:t></w:r></w:p>" for i in range(100))
    path = tmp_path / "long.docx"
    path.write_bytes(archive({"word/document.xml": f"<w:document {W}>{paragraphs}</w:document>"}))

    text = office_text.extract(path, f"{office_text.OPENXML}.wordprocessingml.document", 30)

    assert text.splitlines() == ["Ligne 0", "Ligne 1", "Ligne 2", "Ligne 3"]
