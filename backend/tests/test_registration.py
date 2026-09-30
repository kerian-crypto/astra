import io

from app.models.enums import AccessLevel

REGISTER = "/api/v1/auth/register"
LOGIN = "/api/v1/auth/login"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
PASSWORD = "un-mot-de-passe-solide"


def register(client, email="nouvelle@astra.example.com", photo=None, **fields):
    data = {
        "email": email,
        "password": PASSWORD,
        "first_name": "Awa",
        "last_name": "Diallo",
        "job_title": "Designer UX",
        "requested_access_level": "manager",
        "skills": ["Figma", "UX", "Figma"],
        **fields,
    }
    files = {"photo": photo} if photo else None
    return client.post(REGISTER, data=data, files=files)


def test_registration_creates_a_pending_account_that_cannot_log_in(client, make_user):
    make_user(AccessLevel.ADMIN)

    response = register(client)
    login = client.post(LOGIN, json={"email": "nouvelle@astra.example.com", "password": PASSWORD})
    wrong_password = client.post(
        LOGIN, json={"email": "nouvelle@astra.example.com", "password": "mauvais-mot-de-passe"}
    )

    assert response.status_code == 202
    assert login.status_code == 403
    assert "attente de validation" in login.json()["detail"]
    # Sans le bon mot de passe, rien ne révèle l'existence de la demande.
    assert wrong_password.status_code == 401


def test_admins_are_notified_and_see_the_request(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)
    headers = auth_headers(admin)

    register(client, photo=("moi.png", io.BytesIO(PNG), "image/png"))
    notifications = client.get("/api/v1/notifications", headers=headers).json()
    pending = client.get("/api/v1/users/pending", headers=headers).json()

    assert [n["kind"] for n in notifications] == ["registration_request"]
    (request,) = pending
    assert request["full_name"] == "Awa Diallo"
    assert request["job_title"] == "Designer UX"
    assert request["skills"] == ["Figma", "UX"]
    assert request["requested_access_level"] == "manager"
    assert request["is_active"] is False
    assert request["photo_url"].startswith(f"users/{request['id']}/photo?v=")


def test_pending_requests_are_admin_only_and_hidden_from_directory(client, make_user, auth_headers):
    member = make_user()
    register(client)

    pending = client.get("/api/v1/users/pending", headers=auth_headers(member))
    directory = client.get("/api/v1/users", headers=auth_headers(member)).json()

    assert pending.status_code == 403
    assert "nouvelle@astra.example.com" not in {u["email"] for u in directory}


def test_admin_approves_with_the_final_role(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)
    headers = auth_headers(admin)
    register(client)
    (request,) = client.get("/api/v1/users/pending", headers=headers).json()

    approved = client.post(
        f"/api/v1/users/{request['id']}/approve",
        headers=headers,
        json={"access_level": "member"},
    )
    login = client.post(LOGIN, json={"email": "nouvelle@astra.example.com", "password": PASSWORD})
    again = client.post(
        f"/api/v1/users/{request['id']}/approve", headers=headers, json={"access_level": "member"}
    )

    assert approved.status_code == 200
    # L'admin a préféré « membre » au rôle demandé.
    assert approved.json()["access_level"] == "member"
    assert approved.json()["is_active"] is True
    assert login.status_code == 200
    assert again.status_code == 404


def test_admin_rejects_a_request(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)
    headers = auth_headers(admin)
    register(client)
    (request,) = client.get("/api/v1/users/pending", headers=headers).json()

    rejected = client.post(f"/api/v1/users/{request['id']}/reject", headers=headers)
    pending = client.get("/api/v1/users/pending", headers=headers).json()
    login = client.post(LOGIN, json={"email": "nouvelle@astra.example.com", "password": PASSWORD})

    assert rejected.status_code == 204
    assert pending == []
    assert login.status_code == 401


def test_cannot_request_admin_role(client):
    response = register(client, requested_access_level="admin")

    assert response.status_code == 422


def test_registration_validates_fields(client):
    assert register(client, password="court").status_code == 422
    assert register(client, email="pas-un-email").status_code == 422
    assert register(client, first_name="").status_code == 422
    assert register(client, job_title="").status_code == 422


def test_existing_email_gets_the_same_answer_and_changes_nothing(client, make_user):
    existing = make_user(email="deja@astra.example.com")

    response = register(client, email="deja@astra.example.com")
    login = client.post(
        LOGIN, json={"email": "deja@astra.example.com", "password": "correct-horse-battery"}
    )

    assert response.status_code == 202
    assert login.status_code == 200  # le compte existant n'est pas modifié
    assert existing.full_name != "Awa Diallo"


def test_photo_must_be_a_real_image(client):
    fake = register(client, photo=("moi.png", io.BytesIO(b"<svg onload=alert(1)>"), "image/png"))
    wrong_type = register(
        client, email="b@astra.example.com", photo=("moi.gif", io.BytesIO(b"GIF89a"), "image/gif")
    )

    assert fake.status_code == 400
    assert wrong_type.status_code == 400


def test_registration_is_rate_limited_per_ip(client):
    from app.core.config import get_settings

    for index in range(get_settings().REGISTRATION_RATE_LIMIT):
        register(client, email=f"r{index}@astra.example.com")

    assert register(client, email="trop@astra.example.com").status_code == 429


def test_photo_is_served_only_to_signed_in_members(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)
    headers = auth_headers(admin)
    register(client, photo=("moi.png", io.BytesIO(PNG), "image/png"))
    (request,) = client.get("/api/v1/users/pending", headers=headers).json()
    url = f"/api/v1/{request['photo_url']}"

    anonymous = client.get(url)
    signed_in = client.get(url, headers=headers)

    assert anonymous.status_code == 401
    assert signed_in.status_code == 200
    assert signed_in.headers["content-type"] == "image/png"
    assert signed_in.content == PNG


def test_member_changes_own_photo(client, make_user, auth_headers):
    member = make_user()
    headers = auth_headers(member)

    first = client.put(
        "/api/v1/users/me/photo",
        headers=headers,
        files={"photo": ("a.jpg", io.BytesIO(b"\xff\xd8\xff\xe0" + b"\x00" * 32), "image/jpeg")},
    ).json()
    second = client.put(
        "/api/v1/users/me/photo",
        headers=headers,
        files={"photo": ("b.png", io.BytesIO(PNG), "image/png")},
    ).json()
    photo = client.get(f"/api/v1/{second['photo_url']}", headers=headers)

    assert first["photo_url"] != second["photo_url"]
    assert photo.headers["content-type"] == "image/png"


def test_user_without_photo_has_no_photo_route(client, make_user, auth_headers):
    member = make_user()

    response = client.get(f"/api/v1/users/{member.id}/photo", headers=auth_headers(member))

    assert response.status_code == 404
