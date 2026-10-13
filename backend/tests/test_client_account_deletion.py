"""Suppression de son compte depuis Astra Client (exigence Google Play) :
mot de passe requis, sessions fermées, données personnelles effacées, et
entreprise prospect supprimée avec son dernier compte."""

from sqlalchemy import select

from app.models import ActivityLog, ClientAccount, ClientCompany
from tests.client_fixtures import API, CLIENT_PASSWORD, bearer


def _delete_me(client, headers, password=CLIENT_PASSWORD):
    return client.request(
        "DELETE", f"{API}/client/me", headers=headers, json={"password": password}
    )


def _register(client, email="prospect@example.com"):
    response = client.post(
        f"{API}/client/auth/register",
        json={
            "company_name": "Prospect SARL",
            "full_name": "Awa Prospect",
            "email": email,
            "password": CLIENT_PASSWORD,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_wrong_password_keeps_the_account(client, client_world):
    a = client_world["a"]

    response = _delete_me(client, a["h"], password="pas-le-bon-mot-de-passe")

    # 400 et non 401 : l'app ne doit pas croire la session expirée.
    assert response.status_code == 400
    assert client.get(f"{API}/client/me", headers=a["h"]).status_code == 200


def test_deleting_closes_sessions_and_removes_the_account(client, client_world, db):
    a = client_world["a"]
    email = a["account"]["email"]
    client.patch(f"{API}/client/me", headers=a["h"], json={"phone": "+237 600 00 00 00"})

    response = _delete_me(client, a["h"])

    assert response.status_code == 204
    assert client.get(f"{API}/client/me", headers=a["h"]).status_code == 401
    refresh = client.post(
        f"{API}/client/auth/refresh", json={"refresh_token": a["tokens"]["refresh_token"]}
    )
    assert refresh.status_code == 401
    login = client.post(
        f"{API}/client/auth/login", json={"email": email, "password": CLIENT_PASSWORD}
    )
    assert login.status_code == 401
    assert db.scalar(select(ClientAccount).where(ClientAccount.email == email)) is None
    # Plus aucune trace nominative dans l'historique.
    logs = db.scalars(select(ActivityLog).where(ActivityLog.client_actor_name.is_not(None))).all()
    assert all(log.client_actor_name != a["account"]["full_name"] for log in logs)
    assert not any(
        log.entity_type == "client_account" and str(log.entity_id) == a["account"]["id"]
        for log in logs
    )


def test_company_under_contract_is_kept(client, client_world):
    a = client_world["a"]

    assert _delete_me(client, a["h"]).status_code == 204

    company = client.get(
        f"{API}/clients/companies/{a['company']['id']}", headers=client_world["mh"]
    )
    assert company.status_code == 200
    other = client_world["b"]
    assert client.get(f"{API}/client/me", headers=other["h"]).status_code == 200


def test_last_account_of_a_prospect_deletes_its_company(client, client_world, db):
    tokens = _register(client)
    company_id = client.get(f"{API}/client/me", headers=bearer(tokens["access_token"])).json()[
        "company"
    ]["id"]

    assert _delete_me(client, bearer(tokens["access_token"])).status_code == 204

    assert db.get(ClientCompany, company_id) is None
    # L'entreprise d'un client sous contrat n'est pas touchée.
    assert db.get(ClientCompany, client_world["a"]["company"]["id"]) is not None


def test_prospect_with_remaining_colleague_keeps_its_company(client, client_world, db):
    first = _register(client)
    h = bearer(first["access_token"])
    company_id = client.get(f"{API}/client/me", headers=h).json()["company"]["id"]
    colleague = client.post(
        f"{API}/clients/companies/{company_id}/accounts",
        headers=client_world["mh"],
        json={"email": "collegue@example.com", "full_name": "Collègue"},
    )
    assert colleague.status_code == 201, colleague.text

    assert _delete_me(client, h).status_code == 204

    assert db.get(ClientCompany, company_id) is not None
