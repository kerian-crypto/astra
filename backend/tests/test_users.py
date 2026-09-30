from app.models.enums import AccessLevel
from tests.conftest import DEFAULT_PASSWORD

USERS = "/api/v1/users"
ME = "/api/v1/users/me"


def test_admin_creates_member(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)

    response = client.post(
        USERS,
        headers=auth_headers(admin),
        json={
            "email": "New.Dev@Astra.example.com",
            "password": "a-long-enough-password",
            "full_name": "Nouvelle Dev",
            "job_title": "Développeuse Full Stack",
            "skills": ["Flutter", "FastAPI", "Flutter", " "],
            "availability": 70,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["email"] == "new.dev@astra.example.com"
    assert body["skills"] == ["Flutter", "FastAPI"]
    assert body["access_level"] == "member"
    assert "password" not in body and "password_hash" not in body


def test_non_admin_cannot_create_member(client, make_user, auth_headers):
    manager = make_user(AccessLevel.MANAGER)

    response = client.post(
        USERS,
        headers=auth_headers(manager),
        json={
            "email": "x@astra.example.com",
            "password": "a-long-enough-password",
            "full_name": "X",
        },
    )

    assert response.status_code == 403


def test_create_member_rejects_duplicate_email(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)
    existing = make_user()

    response = client.post(
        USERS,
        headers=auth_headers(admin),
        json={"email": existing.email, "password": "a-long-enough-password", "full_name": "Dup"},
    )

    assert response.status_code == 409


def test_create_member_rejects_short_password(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)

    response = client.post(
        USERS,
        headers=auth_headers(admin),
        json={"email": "s@astra.example.com", "password": "short", "full_name": "S"},
    )

    assert response.status_code == 422


def test_member_updates_own_profile(client, make_user, auth_headers):
    member = make_user()

    response = client.patch(
        ME, headers=auth_headers(member), json={"availability": 40, "skills": ["DevOps"]}
    )

    assert response.status_code == 200
    assert response.json()["availability"] == 40
    assert response.json()["skills"] == ["DevOps"]


def test_member_cannot_escalate_own_access_level(client, make_user, auth_headers):
    member = make_user()

    response = client.patch(ME, headers=auth_headers(member), json={"access_level": "admin"})

    assert response.status_code == 422


def test_profile_update_rejects_null_on_required_field(client, make_user, auth_headers):
    member = make_user()

    response = client.patch(ME, headers=auth_headers(member), json={"full_name": None})

    assert response.status_code == 422


def test_availability_must_be_a_percentage(client, make_user, auth_headers):
    member = make_user()

    response = client.patch(ME, headers=auth_headers(member), json={"availability": 150})

    assert response.status_code == 422


def test_member_cannot_update_another_member(client, make_user, auth_headers):
    member, other = make_user(), make_user()

    response = client.patch(
        f"{USERS}/{other.id}", headers=auth_headers(member), json={"full_name": "Hacked"}
    )

    assert response.status_code == 403


def test_admin_deactivation_revokes_sessions(client, make_user, auth_headers, login):
    admin, member = make_user(AccessLevel.ADMIN), make_user()
    member_tokens = login(member)

    response = client.patch(
        f"{USERS}/{member.id}", headers=auth_headers(admin), json={"is_active": False}
    )
    refresh = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": member_tokens["refresh_token"]}
    )

    assert response.status_code == 200
    assert refresh.status_code == 401


def test_last_admin_cannot_be_demoted(client, make_user, auth_headers):
    admin = make_user(AccessLevel.ADMIN)

    response = client.patch(
        f"{USERS}/{admin.id}", headers=auth_headers(admin), json={"access_level": "member"}
    )

    assert response.status_code == 409


def test_admin_can_be_demoted_when_another_admin_remains(client, make_user, auth_headers):
    admin, other_admin = make_user(AccessLevel.ADMIN), make_user(AccessLevel.ADMIN)

    response = client.patch(
        f"{USERS}/{other_admin.id}", headers=auth_headers(admin), json={"access_level": "manager"}
    )

    assert response.status_code == 200
    assert response.json()["access_level"] == "manager"


def test_directory_hides_inactive_members_from_non_admins(client, db, make_user, auth_headers):
    member, gone = make_user(), make_user()
    gone.is_active = False
    db.commit()

    listed = client.get(f"{USERS}?include_inactive=true", headers=auth_headers(member)).json()

    assert {u["id"] for u in listed} == {str(member.id)}


def test_password_change_requires_current_password(client, make_user, auth_headers):
    member = make_user()

    response = client.post(
        f"{ME}/password",
        headers=auth_headers(member),
        json={"current_password": "wrong", "new_password": "another-long-password"},
    )

    assert response.status_code == 401


def test_password_change_allows_login_with_new_password(client, make_user, auth_headers):
    member = make_user()

    changed = client.post(
        f"{ME}/password",
        headers=auth_headers(member),
        json={"current_password": DEFAULT_PASSWORD, "new_password": "another-long-password"},
    )
    old = client.post(
        "/api/v1/auth/login", json={"email": member.email, "password": DEFAULT_PASSWORD}
    )
    new = client.post(
        "/api/v1/auth/login", json={"email": member.email, "password": "another-long-password"}
    )

    assert changed.status_code == 204
    assert old.status_code == 401
    assert new.status_code == 200


def test_concurrent_admin_demotions_keep_one_admin(make_user, db):
    """Deux admins se rétrogradent en parallèle : le verrou garantit qu'un seul réussit."""
    import threading

    from app.db.session import get_session_factory
    from app.schemas.user import UserAdminUpdate
    from app.services import user_service
    from app.services.errors import ConflictError

    admins = [make_user(AccessLevel.ADMIN), make_user(AccessLevel.ADMIN)]
    barrier = threading.Barrier(2)
    outcomes: list[str] = []

    def demote(user_id):
        with get_session_factory()() as session:
            user = user_service.get_user(session, user_id)
            barrier.wait()
            try:
                user_service.update_by_admin(
                    session, user, UserAdminUpdate(access_level=AccessLevel.MEMBER)
                )
                outcomes.append("ok")
            except ConflictError:
                outcomes.append("conflict")

    threads = [threading.Thread(target=demote, args=(a.id,)) for a in admins]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sorted(outcomes) == ["conflict", "ok"]
