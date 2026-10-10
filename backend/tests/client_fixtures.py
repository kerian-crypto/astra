"""Fixtures du domaine Astra Client : deux entreprises (A et B), chacune avec
un compte client activé et un projet rattaché, gérées par un manager d'Astra.

Enregistrées via `pytest_plugins` dans conftest.py.
"""

from collections.abc import Callable

import pytest
from fastapi.testclient import TestClient

from app.models.client_enums import ClientPermission
from app.models.enums import AccessLevel

API = "/api/v1"
CLIENT_PASSWORD = "client-password-1234"
ALL_PERMISSIONS = [p.value for p in ClientPermission]


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def make_client_account(client: TestClient) -> Callable[..., dict]:
    """Crée un compte via Astra Hub puis l'active avec le lien d'invitation."""
    counter = iter(range(1_000))

    def _make(
        manager_headers: dict,
        company_id: str,
        permissions: list[str] | None = None,
        activate: bool = True,
    ) -> dict:
        index = next(counter)
        response = client.post(
            f"{API}/clients/companies/{company_id}/accounts",
            headers=manager_headers,
            json={
                "email": f"client{index}-{company_id[:6]}@example.com",
                "full_name": f"Client {index}",
                "permissions": ALL_PERMISSIONS if permissions is None else permissions,
            },
        )
        assert response.status_code == 201, response.text
        created = response.json()
        result = {"account": created["account"], "invitation": created["invitation"]}
        if activate:
            tokens = client.post(
                f"{API}/client/auth/activate",
                json={"token": created["invitation"]["token"], "password": CLIENT_PASSWORD},
            )
            assert tokens.status_code == 200, tokens.text
            result["tokens"] = tokens.json()
            result["h"] = bearer(tokens.json()["access_token"])
        return result

    return _make


@pytest.fixture
def client_world(client, make_user, auth_headers, make_client_account) -> dict:
    manager = make_user(AccessLevel.MANAGER)
    mh = auth_headers(manager)
    world: dict = {"manager": manager, "mh": mh}
    for name in ("a", "b"):
        company = client.post(
            f"{API}/clients/companies",
            headers=mh,
            json={"name": f"Entreprise {name.upper()}", "internal_notes": "Client exigeant"},
        ).json()
        project = client.post(
            f"{API}/projects", headers=mh, json={"name": f"Projet {name.upper()}", "budget": "9000"}
        ).json()
        linked = client.patch(
            f"{API}/projects/{project['id']}",
            headers=mh,
            json={"client_company_id": company["id"], "client_summary": "Refonte du site"},
        )
        assert linked.status_code == 200, linked.text
        world[name] = {
            "company": company,
            "project": project,
            **make_client_account(mh, company["id"]),
        }
    return world
