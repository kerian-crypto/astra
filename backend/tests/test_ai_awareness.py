"""Ronda lit toute l'activité d'Astra visible par le membre, et l'écran qu'il consulte.

Aucune lecture ne contourne les permissions : ce qu'un membre ne peut pas
ouvrir dans l'app n'apparaît jamais dans le contexte envoyé à Ronda.
"""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.v1.ai import get_llm
from app.main import create_app
from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind
from tests.test_ai import TODAY, FakeLLM
from tests.test_ai_conversations import InlineJobs

API = "/api/v1"
CONVERSATIONS = f"{API}/ai/conversations"


@pytest.fixture
def llm() -> FakeLLM:
    fake = FakeLLM()
    fake.replies = ["Réponse."] * 5
    return fake


@pytest.fixture
def client(llm) -> Iterator[TestClient]:
    app = create_app()
    app.dependency_overrides[get_llm] = lambda: llm
    with TestClient(app) as test_client:
        app.state.ai_jobs = InlineJobs()
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def general(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def _ask(client, headers, question="Quoi de neuf ?", focus=None):
    body = {"question": question} | ({"focus": focus} if focus else {})
    return client.post(CONVERSATIONS, headers=headers, json=body, params={"today": TODAY})


def _context(llm: FakeLLM) -> str:
    """Contexte envoyé à Ronda (sans la question elle-même)."""
    return llm.prompt_text().split("Question :")[0]


def _post_message(client, headers, channel_id, body):
    response = client.post(
        f"{API}/channels/{channel_id}/messages", headers=headers, json={"body": body}
    )
    assert response.status_code == 201, response.text


def _create_task(client, team, title, **fields):
    response = client.post(
        f"{API}/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": title, **fields},
    )
    assert response.status_code == 201, response.text
    return response.json()


# ---------- Activité récente ----------


def test_recent_activity_of_the_app_reaches_ronda(client, team, general, llm):
    task = _create_task(client, team, "Refonte du tunnel de paiement")
    client.patch(f"{API}/tasks/{task['id']}", headers=team["h"]["lead"], json={"status": "done"})
    _post_message(client, team["h"]["lead"], general["id"], "Livraison prévue vendredi")
    client.post(
        f"{API}/projects/{team['project']['id']}/decisions",
        headers=team["h"]["lead"],
        json={"title": "Adopter Stripe"},
    )

    _ask(client, team["h"]["viewer"])

    context = _context(llm)
    assert "Activité récente" in context
    assert "Refonte du tunnel de paiement" in context
    assert "Livraison prévue vendredi" in context
    assert "Adopter Stripe" in context


def test_activity_of_projects_i_cannot_see_is_never_captured(client, team, llm):
    _create_task(client, team, "Négociation contrat Zephyr")

    _ask(client, team["h"]["outsider"])

    assert "Zephyr" not in _context(llm)


def test_other_members_direct_messages_stay_private(client, make_user, auth_headers, llm):
    alice, bob = make_user(), make_user()
    admin = make_user(AccessLevel.ADMIN)
    direct = client.post(
        f"{API}/channels/direct", headers=auth_headers(alice), json={"user_id": str(bob.id)}
    ).json()
    _post_message(client, auth_headers(alice), direct["id"], "Code du coffre : 4521")

    _ask(client, auth_headers(admin))
    assert "4521" not in _context(llm)

    _ask(client, auth_headers(bob))
    assert "4521" in _context(llm)


# ---------- Écran consulté ----------


def test_focus_on_a_project_gives_ronda_its_details(client, team, llm):
    client.patch(
        f"{API}/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"objective": "Doubler les ventes mobiles"},
    )
    _create_task(client, team, "Maquettes du panier")
    focus = {"type": "project", "id": team["project"]["id"]}

    response = _ask(client, team["h"]["viewer"], "Résume ce projet", focus)

    assert response.status_code == 201, response.text
    context = _context(llm)
    assert "Écran consulté" in context
    assert "Doubler les ventes mobiles" in context
    assert "Maquettes du panier" in context
    question = response.json()["messages"][0]
    assert question["focus_type"] == "project"
    assert question["focus_id"] == team["project"]["id"]
    assert question["focus_title"] == "MarketCM V2"


def test_focus_on_a_task_includes_checklist_and_comments(client, team, llm):
    task = _create_task(client, team, "Intégrer Stripe", description="Paiement par carte")
    url = f"{API}/tasks/{task['id']}"
    client.post(f"{url}/checklist", headers=team["h"]["lead"], json={"label": "Clés de test"})
    client.post(f"{url}/comments", headers=team["h"]["lead"], json={"body": "Attention à la TVA"})

    _ask(client, team["h"]["contributor"], "Où en est-on ?", {"type": "task", "id": task["id"]})

    context = _context(llm)
    assert "Paiement par carte" in context
    assert "Clés de test" in context
    assert "Attention à la TVA" in context


def test_focus_on_a_meeting_includes_its_minutes(client, team, llm):
    meeting = client.post(
        f"{API}/meetings",
        headers=team["h"]["lead"],
        json={
            "title": "Comité produit",
            "scheduled_at": "2026-10-01T09:00:00Z",
            "project_id": team["project"]["id"],
        },
    ).json()
    client.patch(
        f"{API}/meetings/{meeting['id']}",
        headers=team["h"]["lead"],
        json={"minutes": "Budget validé à 12 000 €"},
    )

    _ask(client, team["h"]["viewer"], "Résume", {"type": "meeting", "id": meeting["id"]})

    assert "Budget validé à 12 000 €" in _context(llm)


def test_focus_on_a_channel_includes_its_latest_messages(client, team, general, llm):
    _post_message(client, team["h"]["lead"], general["id"], "Qui relit la spec ?")

    _ask(client, team["h"]["viewer"], "Résume", {"type": "channel", "id": general["id"]})

    context = _context(llm)
    assert "Écran consulté" in context
    assert "Qui relit la spec ?" in context


def test_focus_on_something_i_cannot_see_is_refused(client, team, make_user, auth_headers, llm):
    focus = {"type": "project", "id": team["project"]["id"]}

    response = _ask(client, team["h"]["outsider"], "Résume", focus)

    assert response.status_code == 404
    assert client.get(CONVERSATIONS, headers=team["h"]["outsider"]).json() == []
    assert llm.calls == []


def test_focus_is_validated(client, team):
    bad = {"type": "salary", "id": team["project"]["id"]}

    assert _ask(client, team["h"]["lead"], "Résume", bad).status_code == 422


def test_focus_is_ignored_if_access_is_lost_before_generation(client, team, db, llm):
    """Les droits sont revérifiés au moment où Ronda lit l'écran."""
    from app.ai import focus as ai_focus
    from app.models import User
    from app.schemas.ai import AIFocus

    builder_lines = ai_focus.describe(
        db,
        db.get(User, team["outsider"].id),
        AIFocus(type="project", id=team["project"]["id"]),
    )

    assert builder_lines is None


def test_focus_on_a_decision_and_a_document(client, team, db, llm):
    from app.models import Document
    from app.models.enums import DocumentKind

    decision = client.post(
        f"{API}/projects/{team['project']['id']}/decisions",
        headers=team["h"]["lead"],
        json={"title": "Passer à PostgreSQL 17", "description": "Pour les index GIN"},
    ).json()
    document = Document(
        project_id=team["project"]["id"],
        title="Cahier des charges",
        kind=DocumentKind.SPECIFICATION,
        filename="cdc.txt",
        content_type="text/plain",
        size_bytes=10,
        sha256="0" * 64,
        storage_key="test-key",
        text_content="Le paiement mobile est obligatoire.",
        uploaded_by_id=team["lead"].id,
    )
    db.add(document)
    db.commit()
    viewer = team["h"]["viewer"]

    _ask(client, viewer, "Pourquoi ?", {"type": "decision", "id": decision["id"]})
    assert "Pour les index GIN" in _context(llm)

    _ask(client, viewer, "Résume", {"type": "document", "id": str(document.id)})
    assert "Le paiement mobile est obligatoire." in _context(llm)
