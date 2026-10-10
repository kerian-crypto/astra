"""Astra Client : authentification, séparation des jetons, isolation entre
entreprises et permissions (cahier des charges §9, §11, §39, §70)."""

from app.core.config import get_settings
from app.core.security import create_access_token
from tests.client_fixtures import (
    API,
    CLIENT_PASSWORD,
    bearer,
)


def test_activation_link_is_single_use_and_opens_a_session(client, client_world):
    token = client_world["a"]["invitation"]["token"]

    reused = client.post(
        f"{API}/client/auth/activate", json={"token": token, "password": CLIENT_PASSWORD}
    )

    assert reused.status_code == 400
    assert client.get(f"{API}/client/me", headers=client_world["a"]["h"]).status_code == 200


def test_login_refresh_and_logout(client, client_world):
    email = client_world["a"]["account"]["email"]

    tokens = client.post(
        f"{API}/client/auth/login", json={"email": email, "password": CLIENT_PASSWORD}
    )
    assert tokens.status_code == 200
    refreshed = client.post(
        f"{API}/client/auth/refresh", json={"refresh_token": tokens.json()["refresh_token"]}
    )
    assert refreshed.status_code == 200
    # Réutiliser l'ancien refresh token révoque la session (vol présumé).
    replay = client.post(
        f"{API}/client/auth/refresh", json={"refresh_token": tokens.json()["refresh_token"]}
    )
    assert replay.status_code == 401
    after = client.post(
        f"{API}/client/auth/refresh", json={"refresh_token": refreshed.json()["refresh_token"]}
    )
    assert after.status_code == 401


def test_wrong_password_and_unactivated_account_are_refused_identically(
    client, client_world, make_client_account
):
    pending = make_client_account(
        client_world["mh"], client_world["a"]["company"]["id"], activate=False
    )

    wrong = client.post(
        f"{API}/client/auth/login",
        json={"email": client_world["a"]["account"]["email"], "password": "nope-nope-nope"},
    )
    inactive = client.post(
        f"{API}/client/auth/login",
        json={"email": pending["account"]["email"], "password": CLIENT_PASSWORD},
    )

    assert wrong.status_code == inactive.status_code == 401
    assert wrong.json() == inactive.json()


def test_client_token_is_refused_on_every_hub_route(client, client_world):
    headers = client_world["a"]["h"]
    for path in (
        "/users",
        "/projects",
        "/documents",
        "/channels",
        "/notifications",
        "/dashboard",
        "/me/work",
        f"/projects/{client_world['a']['project']['id']}",
    ):
        response = client.get(f"{API}{path}", headers=headers)
        assert response.status_code == 401, path


def test_member_token_is_refused_on_client_routes(client, client_world):
    member_token = create_access_token(client_world["manager"].id, get_settings())

    response = client.get(f"{API}/client/projects", headers=bearer(member_token))

    assert response.status_code == 401


def test_deactivated_account_loses_access_immediately(client, client_world):
    account_id = client_world["a"]["account"]["id"]

    client.patch(
        f"{API}/clients/accounts/{account_id}",
        headers=client_world["mh"],
        json={"is_active": False},
    )

    assert client.get(f"{API}/client/me", headers=client_world["a"]["h"]).status_code == 401


def test_deactivated_company_blocks_its_accounts(client, client_world):
    company_id = client_world["a"]["company"]["id"]

    client.patch(
        f"{API}/clients/companies/{company_id}",
        headers=client_world["mh"],
        json={"is_active": False},
    )

    assert client.get(f"{API}/client/me", headers=client_world["a"]["h"]).status_code == 401


def test_password_reset_link_replaces_the_password(client, client_world):
    account_id = client_world["a"]["account"]["id"]

    link = client.post(
        f"{API}/clients/accounts/{account_id}/invitation", headers=client_world["mh"]
    ).json()
    reset = client.post(
        f"{API}/client/auth/activate",
        json={"token": link["token"], "password": "brand-new-password"},
    )

    assert link["purpose"] == "password_reset"
    assert reset.status_code == 200
    old_login = client.post(
        f"{API}/client/auth/login",
        json={"email": client_world["a"]["account"]["email"], "password": CLIENT_PASSWORD},
    )
    assert old_login.status_code == 401


# ---------- Isolation entre entreprises (§70) ----------


def test_client_a_cannot_see_project_b(client, client_world):
    a, b = client_world["a"], client_world["b"]

    listing = client.get(f"{API}/client/projects", headers=a["h"]).json()
    direct = client.get(f"{API}/client/projects/{b['project']['id']}", headers=a["h"])

    assert [p["id"] for p in listing] == [a["project"]["id"]]
    assert direct.status_code == 404
    assert (
        client.get(
            f"{API}/client/projects/{b['project']['id']}/timeline", headers=a["h"]
        ).status_code
        == 404
    )


def test_project_view_never_exposes_internal_data(client, client_world):
    a = client_world["a"]

    view = client.get(f"{API}/client/projects/{a['project']['id']}", headers=a["h"]).json()
    me = client.get(f"{API}/client/me", headers=a["h"]).json()

    for internal in ("budget", "members", "my_role", "objective", "priority", "created_by_id"):
        assert internal not in view
    assert "internal_notes" not in me["company"]
    assert view["summary"] == "Refonte du site"
    assert all(set(member) == {"full_name", "job_title", "is_lead"} for member in view["team"])


def test_internal_project_is_invisible_to_every_client(client, client_world):
    internal = client.post(
        f"{API}/projects", headers=client_world["mh"], json={"name": "Interne"}
    ).json()

    response = client.get(f"{API}/client/projects/{internal['id']}", headers=client_world["a"]["h"])

    assert response.status_code == 404


def test_permissions_are_enforced_server_side(client, client_world, make_client_account):
    limited = make_client_account(
        client_world["mh"], client_world["a"]["company"]["id"], permissions=["send_message"]
    )

    for path in (
        "/projects",
        "/invoices",
        "/contracts",
        "/tickets",
        "/documents",
        "/company/users",
    ):
        assert client.get(f"{API}/client{path}", headers=limited["h"]).status_code == 403, path
    assert client.get(f"{API}/client/dashboard", headers=limited["h"]).status_code == 200


def test_only_managers_link_projects_to_clients(client, client_world, make_user, auth_headers):
    lead = make_user()
    project = client.post(
        f"{API}/projects",
        headers=client_world["mh"],
        json={"name": "Projet confié", "lead_id": str(lead.id)},
    ).json()

    response = client.patch(
        f"{API}/projects/{project['id']}",
        headers=auth_headers(lead),
        json={"client_company_id": client_world["a"]["company"]["id"]},
    )

    assert response.status_code == 403


def test_members_cannot_administer_clients(client, make_user, auth_headers):
    member = auth_headers(make_user())

    assert client.get(f"{API}/clients/companies", headers=member).status_code == 403
    assert (
        client.post(f"{API}/clients/companies", headers=member, json={"name": "X"}).status_code
        == 403
    )


def test_client_actions_are_audited_in_activity_log(client, client_world, db):
    from sqlalchemy import select

    from app.models import ActivityLog

    actions = set(
        db.scalars(select(ActivityLog.action).where(ActivityLog.client_account_id.is_not(None)))
    )

    assert {"activated"} <= actions


def test_profile_update_and_company_users(client, client_world):
    a = client_world["a"]

    updated = client.patch(f"{API}/client/me", headers=a["h"], json={"phone": "+221 77 000 00 00"})
    company = client.patch(f"{API}/client/company", headers=a["h"], json={"sector": "Retail"})
    renamed = client.patch(f"{API}/client/company", headers=a["h"], json={"name": "Pirate"})
    users = client.get(f"{API}/client/company/users", headers=a["h"]).json()

    assert updated.json()["phone"] == "+221 77 000 00 00"
    assert company.json()["sector"] == "Retail"
    assert renamed.status_code == 422  # nom : donnée sensible gérée par Astra
    assert [u["id"] for u in users] == [a["account"]["id"]]
