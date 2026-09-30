"""Correctifs de sécurité : jeton exposé via une photo externe, mémoire du
limiteur, et remplissage du disque par des envois répétés."""

import pytest

from app.core import rate_limit
from app.core.rate_limit import SlidingWindowRateLimiter
from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind

API = "/api/v1"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


# ---------- Photo de profil : jamais d'URL externe ----------


@pytest.mark.parametrize("path", ["/users/me"])
def test_members_cannot_point_their_photo_to_an_external_site(
    client, make_user, auth_headers, path
):
    """Une URL externe ferait envoyer le jeton de chaque lecteur à ce site."""
    headers = auth_headers(make_user())

    response = client.patch(
        f"{API}{path}", headers=headers, json={"photo_url": "https://attacker.example/x.png"}
    )

    assert response.status_code == 422


def test_admins_cannot_set_an_external_photo_either(client, make_user, auth_headers):
    admin = auth_headers(make_user(AccessLevel.ADMIN))
    member = make_user()

    response = client.patch(
        f"{API}/users/{member.id}",
        headers=admin,
        json={"photo_url": "https://attacker.example/x.png"},
    )

    assert response.status_code == 422


def test_existing_external_photos_are_no_longer_exposed(client, make_user, auth_headers, db):
    member = make_user()
    member.photo_url = "https://attacker.example/x.png"
    db.commit()

    body = client.get(f"{API}/users/me", headers=auth_headers(member)).json()

    assert body["photo_url"] is None


# ---------- Limiteur : pas de croissance mémoire illimitée ----------


def test_rate_limiter_forgets_keys_once_their_window_has_passed(monkeypatch):
    clock = [1_000.0]
    monkeypatch.setattr(rate_limit.time, "monotonic", lambda: clock[0])
    limiter = SlidingWindowRateLimiter(max_attempts=3, window_seconds=60)

    for index in range(500):
        limiter.record_failure(f"ip:intrus{index}@example.com")
    clock[0] += 61
    limiter.record_failure("ip:dernier@example.com")

    assert limiter.tracked_keys() == 1


def test_rate_limiter_still_blocks_within_the_window(monkeypatch):
    clock = [1_000.0]
    monkeypatch.setattr(rate_limit.time, "monotonic", lambda: clock[0])
    limiter = SlidingWindowRateLimiter(max_attempts=2, window_seconds=60)

    limiter.record_failure("k")
    limiter.record_failure("k")
    assert limiter.is_blocked("k")
    assert not limiter.is_blocked("autre")
    clock[0] += 61
    assert not limiter.is_blocked("k")
    assert limiter.tracked_keys() == 0


# ---------- Envois de fichiers : fréquence limitée par membre ----------


@pytest.fixture
def general(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def test_uploads_are_rate_limited_per_member(client, make_user, auth_headers, general):
    client.app.state.upload_limiter = SlidingWindowRateLimiter(2, 3600)
    headers, other = auth_headers(make_user()), auth_headers(make_user())

    def upload(h):
        return client.post(
            f"{API}/channels/{general['id']}/attachments",
            headers=h,
            files={"file": ("photo.png", PNG)},
        )

    assert [upload(headers).status_code for _ in range(3)] == [201, 201, 429]
    assert upload(other).status_code == 201


def test_channel_photo_changes_count_as_uploads(client, make_user, auth_headers, general):
    client.app.state.upload_limiter = SlidingWindowRateLimiter(1, 3600)
    admin = auth_headers(make_user(AccessLevel.ADMIN))

    def put_photo():
        return client.put(
            f"{API}/channels/{general['id']}/photo",
            headers=admin,
            files={"photo": ("logo.png", PNG)},
        )

    assert [put_photo().status_code, put_photo().status_code] == [200, 429]
