import io

from app.models.enums import AccessLevel

MINIMAL_PDF = (
    b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
    b"2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF"
)


def upload(client, headers, url, filename, content, title="Spécifications", kind="specification"):
    return client.post(
        url,
        headers=headers,
        data={"title": title, "kind": kind},
        files={"file": (filename, io.BytesIO(content), "application/octet-stream")},
    )


def project_docs(team):
    return f"/api/v1/projects/{team['project']['id']}/documents"


def test_contributor_uploads_text_document_which_is_indexed(client, team):
    response = upload(
        client, team["h"]["contributor"], project_docs(team), "spec.md", b"# API\nFastAPI retenu."
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["content_type"].startswith("text/markdown")
    assert body["is_indexed"] is True
    assert body["size_bytes"] == len(b"# API\nFastAPI retenu.")


def test_viewer_cannot_upload_and_outsider_cannot_list(client, team):
    viewer = upload(client, team["h"]["viewer"], project_docs(team), "a.txt", b"x")
    outsider = client.get(project_docs(team), headers=team["h"]["outsider"])

    assert viewer.status_code == 403
    assert outsider.status_code == 404


def test_rejects_unknown_extension(client, team):
    response = upload(client, team["h"]["lead"], project_docs(team), "script.sh", b"rm -rf /")

    assert response.status_code == 400
    assert "Format non accepté" in response.json()["detail"]


def test_rejects_content_not_matching_extension(client, team):
    response = upload(client, team["h"]["lead"], project_docs(team), "faux.pdf", b"<html>")

    assert response.status_code == 400


def test_rejects_binary_disguised_as_text(client, team):
    response = upload(client, team["h"]["lead"], project_docs(team), "notes.txt", b"\x00\x01ELF")

    assert response.status_code == 400


def test_pdf_is_accepted(client, team):
    response = upload(client, team["h"]["lead"], project_docs(team), "cdc.pdf", MINIMAL_PDF)

    assert response.status_code == 201, response.text
    assert response.json()["content_type"] == "application/pdf"


def test_rejects_oversized_file(client, team):
    from app.core.config import get_settings

    too_big = b"a" * (get_settings().MAX_UPLOAD_BYTES + 1)

    response = upload(client, team["h"]["lead"], project_docs(team), "big.txt", too_big)

    assert response.status_code == 400
    assert "volumineux" in response.json()["detail"]


def test_filename_path_is_stripped(client, team):
    response = upload(
        client, team["h"]["lead"], project_docs(team), "../../etc/passwd.txt", b"contenu"
    )

    assert response.json()["filename"] == "passwd.txt"


def test_download_is_forced_as_attachment(client, team):
    document = upload(
        client, team["h"]["lead"], project_docs(team), "cr.txt", b"Compte rendu"
    ).json()

    response = client.get(
        f"/api/v1/documents/{document['id']}/download", headers=team["h"]["viewer"]
    )
    outsider = client.get(
        f"/api/v1/documents/{document['id']}/download", headers=team["h"]["outsider"]
    )

    assert response.status_code == 200
    assert response.content == b"Compte rendu"
    assert response.headers["content-disposition"].startswith("attachment;")
    assert response.headers["x-content-type-options"] == "nosniff"
    assert outsider.status_code == 404


def test_delete_by_uploader_or_lead_only(client, team):
    document = upload(client, team["h"]["contributor"], project_docs(team), "a.txt", b"x").json()
    url = f"/api/v1/documents/{document['id']}"

    assert client.delete(url, headers=team["h"]["viewer"]).status_code == 403
    assert client.delete(url, headers=team["h"]["lead"]).status_code == 204
    assert client.get(url, headers=team["h"]["lead"]).status_code == 404


def test_general_documents_need_manager_and_are_visible_to_all(client, make_user, auth_headers):
    member, manager = make_user(), make_user(AccessLevel.MANAGER)

    by_member = upload(client, auth_headers(member), "/api/v1/documents", "g.md", b"Guide")
    by_manager = upload(
        client, auth_headers(manager), "/api/v1/documents", "g.md", b"Guide", kind="guide"
    )
    listed = client.get("/api/v1/documents", headers=auth_headers(member)).json()

    assert by_member.status_code == 403
    assert by_manager.status_code == 201
    assert [d["title"] for d in listed] == ["Spécifications"]


def test_oversized_pdf_is_stored_but_not_indexed(client, team, monkeypatch):
    from app.services import file_types

    monkeypatch.setattr(file_types, "MAX_PDF_PAGES", -1)

    response = upload(client, team["h"]["lead"], project_docs(team), "gros.pdf", MINIMAL_PDF)

    assert response.status_code == 201
    assert response.json()["is_indexed"] is False
