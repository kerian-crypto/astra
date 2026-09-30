"""Messages avec pièce jointe : photo, vidéo, message vocal et document."""

import pytest

from app.core.config import get_settings
from app.main import create_app
from app.models import Channel
from app.models.enums import ChannelKind

API = "/api/v1"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
M4A = b"\x00\x00\x00\x20ftypM4A " + b"\x00" * 64
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64
PDF = b"%PDF-1.7\n" + b"x" * 64


@pytest.fixture
def general(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def _upload(client, headers, channel_id, filename, content, **form):
    return client.post(
        f"{API}/channels/{channel_id}/attachments",
        headers=headers,
        files={"file": (filename, content)},
        data=form,
    )


@pytest.mark.parametrize(
    ("filename", "content", "kind", "content_type"),
    [
        ("photo.png", PNG, "image", "image/png"),
        ("clip.mp4", MP4, "video", "video/mp4"),
        ("vocal.m4a", M4A, "audio", "audio/mp4"),
        ("devis.pdf", PDF, "file", "application/pdf"),
    ],
)
def test_each_attachment_kind_is_posted_and_downloaded(
    client, make_user, auth_headers, general, filename, content, kind, content_type
):
    author, reader = auth_headers(make_user()), auth_headers(make_user())

    response = _upload(client, author, general["id"], filename, content)

    assert response.status_code == 201, response.text
    message = response.json()
    assert message["body"] == ""
    assert message["attachment"] == {
        "kind": kind,
        "name": filename,
        "content_type": content_type,
        "size_bytes": len(content),
        "duration_ms": None,
    }
    listed = client.get(f"{API}/channels/{general['id']}/messages", headers=reader).json()
    assert listed[0]["attachment"]["kind"] == kind

    download = client.get(f"{API}/messages/{message['id']}/attachment", headers=reader)
    assert download.status_code == 200
    assert download.content == content
    assert download.headers["content-type"].startswith(content_type)
    assert download.headers["x-content-type-options"] == "nosniff"
    disposition = "attachment" if kind == "file" else "inline"
    assert download.headers["content-disposition"].startswith(disposition)


def test_voice_note_keeps_caption_and_duration(client, make_user, auth_headers, general):
    headers = auth_headers(make_user())

    message = _upload(
        client, headers, general["id"], "vocal.m4a", M4A, body="Écoute ça", duration_ms="4200"
    ).json()

    assert message["body"] == "Écoute ça"
    assert message["attachment"]["duration_ms"] == 4200


def test_content_must_match_the_extension(client, make_user, auth_headers, general):
    headers = auth_headers(make_user())

    fake = _upload(client, headers, general["id"], "photo.png", b"<html>hello</html>")
    unsupported = _upload(client, headers, general["id"], "virus.exe", b"MZ" + b"\x00" * 30)
    empty = _upload(client, headers, general["id"], "vide.pdf", b"")

    assert fake.status_code == 400
    assert unsupported.status_code == 400
    assert empty.status_code == 400
    assert client.get(f"{API}/channels/{general['id']}/messages", headers=headers).json() == []


def test_files_larger_than_the_limit_are_refused(make_user, auth_headers, general):
    from fastapi.testclient import TestClient

    settings = get_settings().model_copy(update={"MAX_CHAT_UPLOAD_BYTES": 32})
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    with TestClient(app) as small_client:
        headers = auth_headers(make_user())
        response = _upload(small_client, headers, general["id"], "photo.png", PNG)

    assert response.status_code == 400
    assert "volumineux" in response.json()["detail"]


def test_only_channel_members_can_download(client, make_user, auth_headers):
    alice, bob, carol = make_user(), make_user(), make_user()
    direct = client.post(
        f"{API}/channels/direct", headers=auth_headers(alice), json={"user_id": str(bob.id)}
    ).json()
    message = _upload(client, auth_headers(alice), direct["id"], "photo.png", PNG).json()
    url = f"{API}/messages/{message['id']}/attachment"

    assert client.get(url, headers=auth_headers(bob)).status_code == 200
    assert client.get(url, headers=auth_headers(carol)).status_code == 404
    assert client.get(url).status_code == 401


def test_announcement_channels_refuse_member_uploads(client, make_user, auth_headers, db):
    channel = Channel(kind=ChannelKind.PUBLIC, name="annonces", announcements_only=True)
    db.add(channel)
    db.commit()

    response = _upload(client, auth_headers(make_user()), str(channel.id), "photo.png", PNG)

    assert response.status_code == 403


def test_deleting_the_message_removes_the_file(client, make_user, auth_headers, general):
    author = make_user()
    headers = auth_headers(author)
    message = _upload(client, headers, general["id"], "photo.png", PNG).json()

    deleted = client.delete(f"{API}/messages/{message['id']}", headers=headers).json()

    assert deleted["attachment"] is None
    assert (
        client.get(f"{API}/messages/{message['id']}/attachment", headers=headers).status_code == 404
    )


def test_text_message_has_no_attachment(client, make_user, auth_headers, general):
    headers = auth_headers(make_user())
    response = client.post(
        f"{API}/channels/{general['id']}/messages", headers=headers, json={"body": "Salut"}
    )

    assert response.json()["attachment"] is None
    assert (
        client.get(
            f"{API}/messages/{response.json()['id']}/attachment", headers=headers
        ).status_code
        == 404
    )


def test_ronda_knows_a_file_was_shared(client, make_user, auth_headers, general, db):
    from app.ai import activity
    from app.models import User

    author = make_user()
    _upload(client, auth_headers(author), general["id"], "devis.pdf", PDF, body="Le devis")

    lines = activity.messages(db, db.get(User, author.id))

    assert "Le devis" in lines[0]
    assert "[document : devis.pdf]" in lines[0]
