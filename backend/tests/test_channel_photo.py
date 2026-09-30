"""Photo des canaux : modifiable par ceux qui gèrent le canal, visible de ceux qui y ont accès."""

import pytest

from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind

API = "/api/v1"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest.fixture
def general(db) -> dict:
    # Canal créé par `seed-channels` : aucun créateur, géré par les administrateurs.
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def _put_photo(client, headers, channel_id, filename="logo.png", content=PNG):
    return client.put(
        f"{API}/channels/{channel_id}/photo",
        headers=headers,
        files={"photo": (filename, content)},
    )


def test_admin_sets_a_channel_photo_that_members_can_see(client, make_user, auth_headers, general):
    admin = auth_headers(make_user(AccessLevel.ADMIN))
    member = auth_headers(make_user())

    response = _put_photo(client, admin, general["id"])

    assert response.status_code == 200, response.text
    photo_url = response.json()["photo_url"]
    assert photo_url.startswith(f"channels/{general['id']}/photo?v=")
    listed = {c["id"]: c for c in client.get(f"{API}/channels", headers=member).json()}
    assert listed[general["id"]]["photo_url"] == photo_url
    assert listed[general["id"]]["can_manage"] is False
    photo = client.get(f"{API}/{photo_url}", headers=member)
    assert photo.status_code == 200
    assert photo.content == PNG
    assert photo.headers["content-type"] == "image/png"
    assert photo.headers["x-content-type-options"] == "nosniff"


def test_members_who_do_not_manage_the_channel_cannot_change_it(
    client, make_user, auth_headers, general
):
    response = _put_photo(client, auth_headers(make_user()), general["id"])

    assert response.status_code == 403


def test_creator_of_a_private_group_manages_its_photo(client, make_user, auth_headers):
    owner, outsider = make_user(AccessLevel.MANAGER), make_user()
    headers = auth_headers(owner)
    group = client.post(
        f"{API}/channels", headers=headers, json={"kind": "private", "name": "équipe"}
    ).json()
    assert group["can_manage"] is True

    photo_url = _put_photo(client, headers, group["id"], "logo.jpg", JPEG).json()["photo_url"]

    assert client.get(f"{API}/{photo_url}", headers=headers).headers["content-type"] == "image/jpeg"
    assert client.get(f"{API}/{photo_url}", headers=auth_headers(outsider)).status_code == 404


def test_replacing_then_removing_the_photo(client, make_user, auth_headers, general):
    admin = auth_headers(make_user(AccessLevel.ADMIN))
    first = _put_photo(client, admin, general["id"]).json()["photo_url"]
    second = _put_photo(client, admin, general["id"], "logo.jpg", JPEG).json()["photo_url"]
    assert first != second

    removed = client.delete(f"{API}/channels/{general['id']}/photo", headers=admin)

    assert removed.status_code == 200
    assert removed.json()["photo_url"] is None
    assert client.get(f"{API}/channels/{general['id']}/photo", headers=admin).status_code == 404


def test_only_png_and_jpeg_images_are_accepted(client, make_user, auth_headers, general):
    admin = auth_headers(make_user(AccessLevel.ADMIN))

    assert _put_photo(client, admin, general["id"], "logo.gif", b"GIF89a....").status_code == 400
    assert _put_photo(client, admin, general["id"], "logo.png", b"<svg></svg>").status_code == 400


def test_direct_conversation_shows_the_other_member_photo(client, make_user, auth_headers, db):
    alice, bob = make_user(), make_user()
    uploaded = client.put(
        f"{API}/users/me/photo", headers=auth_headers(bob), files={"photo": ("bob.png", PNG)}
    ).json()["photo_url"]

    direct = client.post(
        f"{API}/channels/direct", headers=auth_headers(alice), json={"user_id": str(bob.id)}
    ).json()

    assert direct["photo_url"] == uploaded
    assert uploaded.startswith(f"users/{bob.id}/photo?v=")
    assert direct["can_manage"] is False
    assert _put_photo(client, auth_headers(alice), direct["id"]).status_code == 403
