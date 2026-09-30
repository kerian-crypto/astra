from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import update

from app.core.config import get_settings
from app.core.security import TOKEN_AUDIENCE, TOKEN_ISSUER, create_access_token
from app.models import RefreshToken
from tests.conftest import DEFAULT_PASSWORD

LOGIN = "/api/v1/auth/login"
REFRESH = "/api/v1/auth/refresh"
LOGOUT = "/api/v1/auth/logout"
ME = "/api/v1/users/me"


def test_login_returns_token_pair_usable_on_protected_route(client, make_user):
    user = make_user()

    response = client.post(LOGIN, json={"email": user.email, "password": DEFAULT_PASSWORD})

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 15 * 60
    me = client.get(ME, headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200
    assert me.json()["email"] == user.email


def test_login_is_case_insensitive_on_email(client, make_user):
    user = make_user(email="alice@astra.example.com")

    response = client.post(
        LOGIN, json={"email": "  Alice@Astra.EXAMPLE.com ", "password": DEFAULT_PASSWORD}
    )

    assert response.status_code == 200
    assert user.email == "alice@astra.example.com"


def test_login_rejects_wrong_password_and_unknown_email_identically(client, make_user):
    user = make_user()

    wrong_password = client.post(LOGIN, json={"email": user.email, "password": "nope"})
    unknown_email = client.post(
        LOGIN, json={"email": "ghost@astra.example.com", "password": "nope"}
    )

    assert wrong_password.status_code == unknown_email.status_code == 401
    assert wrong_password.json() == unknown_email.json()


def test_login_rejects_inactive_member(client, db, make_user):
    user = make_user()
    user.is_active = False
    db.commit()

    response = client.post(LOGIN, json={"email": user.email, "password": DEFAULT_PASSWORD})

    assert response.status_code == 401


def test_login_is_rate_limited_after_repeated_failures(client, make_user):
    user = make_user()
    attempts = get_settings().LOGIN_RATE_LIMIT_ATTEMPTS
    for _ in range(attempts):
        client.post(LOGIN, json={"email": user.email, "password": "wrong"})

    # Même le bon mot de passe est refusé tant que la fenêtre n'est pas écoulée.
    response = client.post(LOGIN, json={"email": user.email, "password": DEFAULT_PASSWORD})

    assert response.status_code == 429


def test_protected_route_requires_token(client):
    assert client.get(ME).status_code == 401


def test_protected_route_rejects_expired_token(client, make_user):
    user = make_user()
    settings = get_settings()
    past = datetime.now(UTC) - timedelta(hours=1)
    token = jwt.encode(
        {
            "sub": str(user.id),
            "type": "access",
            "iss": TOKEN_ISSUER,
            "aud": TOKEN_AUDIENCE,
            "iat": past,
            "exp": past + timedelta(minutes=1),
        },
        settings.SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )

    assert client.get(ME, headers={"Authorization": f"Bearer {token}"}).status_code == 401


def test_protected_route_rejects_token_signed_with_other_key(client, make_user):
    user = make_user()
    forged = create_access_token(
        user.id, get_settings().model_copy(update={"SECRET_KEY": "x" * 40})
    )

    assert client.get(ME, headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_deactivated_member_loses_access_immediately(client, db, make_user, auth_headers):
    user = make_user()
    headers = auth_headers(user)
    user.is_active = False
    db.commit()

    assert client.get(ME, headers=headers).status_code == 401


def test_refresh_rotates_tokens(client, make_user, login):
    tokens = login(make_user())

    response = client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]})

    assert response.status_code == 200
    assert response.json()["refresh_token"] != tokens["refresh_token"]


def test_reusing_a_refresh_token_revokes_the_whole_session(client, make_user, login):
    tokens = login(make_user())
    rotated = client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]}).json()

    replay = client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]})
    after_replay = client.post(REFRESH, json={"refresh_token": rotated["refresh_token"]})

    assert replay.status_code == 401
    assert after_replay.status_code == 401


def test_expired_refresh_token_is_rejected(client, db, make_user, login):
    tokens = login(make_user())
    db.execute(update(RefreshToken).values(expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    db.commit()

    response = client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]})

    assert response.status_code == 401


def test_unknown_refresh_token_is_rejected(client):
    assert client.post(REFRESH, json={"refresh_token": "made-up"}).status_code == 401


def test_logout_revokes_refresh_token_and_is_idempotent(client, make_user, login):
    tokens = login(make_user())

    first = client.post(LOGOUT, json={"refresh_token": tokens["refresh_token"]})
    second = client.post(LOGOUT, json={"refresh_token": tokens["refresh_token"]})
    refresh = client.post(REFRESH, json={"refresh_token": tokens["refresh_token"]})

    assert first.status_code == second.status_code == 204
    assert refresh.status_code == 401


def test_logout_does_not_affect_other_sessions(client, make_user, login):
    user = make_user()
    phone, laptop = login(user), login(user)

    client.post(LOGOUT, json={"refresh_token": phone["refresh_token"]})

    assert client.post(REFRESH, json={"refresh_token": laptop["refresh_token"]}).status_code == 200
