"""Actions proposées par Ronda : l'IA propose, le membre valide.

Rien n'est créé tant que le membre n'a pas validé, et la validation passe par
les services habituels : mêmes droits que dans l'app.
"""

import json
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.v1.ai import get_llm
from app.main import create_app
from app.models.enums import AccessLevel
from tests.test_ai import TODAY, FakeLLM
from tests.test_ai_conversations import InlineJobs

API = "/api/v1"
CONVERSATIONS = f"{API}/ai/conversations"


def reply(answer: str, kind: str = "none", **fields) -> str:
    action = {
        "kind": kind,
        "title": "",
        "description": "",
        "project_number": None,
        "date": None,
        "time": None,
        "duration_minutes": None,
        "priority": None,
    } | fields
    return json.dumps({"answer": answer, "action": action})


@pytest.fixture
def llm() -> FakeLLM:
    return FakeLLM()


@pytest.fixture
def client(llm) -> Iterator[TestClient]:
    app = create_app()
    app.dependency_overrides[get_llm] = lambda: llm
    with TestClient(app) as test_client:
        app.state.ai_jobs = InlineJobs()
        yield test_client
    app.dependency_overrides.clear()


def _ask(client, headers, question, focus=None, offset=0):
    body = {"question": question, "utc_offset_minutes": offset}
    if focus:
        body["focus"] = focus
    response = client.post(CONVERSATIONS, headers=headers, json=body, params={"today": TODAY})
    assert response.status_code == 201, response.text
    return response.json()


def _decide(client, headers, conversation, apply=True):
    message = conversation["messages"][-1]
    return client.post(
        f"{CONVERSATIONS}/{conversation['id']}/messages/{message['id']}/action",
        headers=headers,
        json={"apply": apply},
    )


def test_ronda_proposes_a_project_and_nothing_is_created_before_validation(
    client, make_user, auth_headers, llm
):
    headers = auth_headers(make_user(AccessLevel.MANAGER))
    llm.replies = [
        reply(
            "Je vous propose ce projet.",
            "create_project",
            title="Application livreurs",
            description="Suivi des livraisons",
            date="2026-12-15",
            priority="high",
        )
    ]

    conversation = _ask(client, headers, "Crée un projet Application livreurs")

    action = conversation["messages"][-1]["action"]
    assert action["kind"] == "create_project"
    assert action["status"] == "proposed"
    assert action["title"] == "Créer le projet « Application livreurs »"
    assert "Échéance : 15/12/2026" in action["details"]
    assert client.get(f"{API}/projects", headers=headers).json() == []
    assert "json_schema" in llm.calls[-1] and llm.calls[-1]["json_schema"]

    applied = _decide(client, headers, conversation)

    assert applied.status_code == 200, applied.text
    action = applied.json()["action"]
    assert action["status"] == "applied"
    assert action["result_type"] == "project"
    project = client.get(f"{API}/projects/{action['result_id']}", headers=headers).json()
    assert (project["name"], project["priority"]) == ("Application livreurs", "high")


def test_members_who_cannot_create_projects_get_no_proposal(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())
    llm.replies = [reply("C'est parti.", "create_project", title="Projet X")]

    message = _ask(client, headers, "Crée le projet X")["messages"][-1]

    assert message["action"] is None
    assert "managers" in message["content"]


def test_meeting_time_is_read_in_the_member_timezone(client, team, llm):
    headers = team["h"]["lead"]
    llm.replies = [
        reply(
            "Réunion proposée.",
            "schedule_meeting",
            title="Revue sprint",
            description="1. Démo",
            date="2026-10-05",
            time="14:30",
            duration_minutes=45,
        )
    ]
    focus = {"type": "project", "id": team["project"]["id"]}

    conversation = _ask(client, headers, "Planifie la revue lundi 14h30", focus, offset=60)
    applied = _decide(client, headers, conversation).json()["action"]

    meeting = client.get(f"{API}/meetings/{applied['result_id']}", headers=headers).json()
    assert meeting["scheduled_at"].startswith("2026-10-05T13:30")
    assert meeting["duration_minutes"] == 45
    assert meeting["project_id"] == team["project"]["id"]
    assert meeting["agenda"] == "1. Démo"


def test_meeting_without_a_date_is_not_proposed(client, team, llm):
    llm.replies = [reply("Quand ?", "schedule_meeting", title="Point")]

    message = _ask(client, team["h"]["lead"], "Planifie un point")["messages"][-1]

    assert message["action"] is None


def test_task_uses_the_screen_being_viewed_as_project(client, team, llm):
    llm.replies = [
        reply("Tâche proposée.", "create_task", title="Tests de charge", date="2026-10-10")
    ]
    focus = {"type": "project", "id": team["project"]["id"]}

    conversation = _ask(client, team["h"]["contributor"], "Ajoute une tâche", focus)
    action = conversation["messages"][-1]["action"]
    assert "Projet : MarketCM V2" in action["details"]

    applied = _decide(client, team["h"]["contributor"], conversation).json()["action"]
    task = client.get(f"{API}/tasks/{applied['result_id']}", headers=team["h"]["lead"]).json()
    assert (task["title"], task["due_date"]) == ("Tests de charge", "2026-10-10")


def test_project_can_be_designated_by_its_context_number(client, team, llm):
    # Le lead n'a aucune tâche : le projet est la première source du contexte.
    llm.replies = [
        reply("Décision notée.", "create_decision", title="Garder Flutter", project_number=1)
    ]

    conversation = _ask(client, team["h"]["lead"], "Note la décision de garder Flutter")
    applied = _decide(client, team["h"]["lead"], conversation).json()["action"]

    assert applied["result_type"] == "decision"
    decision = client.get(
        f"{API}/decisions/{applied['result_id']}", headers=team["h"]["lead"]
    ).json()
    assert (decision["title"], decision["project_id"]) == (
        "Garder Flutter",
        team["project"]["id"],
    )


def test_task_without_project_is_not_proposed(client, team, llm):
    llm.replies = [reply("Dans quel projet ?", "create_task", title="Tests")]

    message = _ask(client, team["h"]["lead"], "Ajoute une tâche Tests")["messages"][-1]

    assert message["action"] is None
    assert "projet" in message["content"]


def test_validation_uses_the_member_rights(client, team, llm):
    llm.replies = [reply("Tâche proposée.", "create_task", title="Audit")]
    focus = {"type": "project", "id": team["project"]["id"]}
    conversation = _ask(client, team["h"]["viewer"], "Ajoute une tâche Audit", focus)

    refused = _decide(client, team["h"]["viewer"], conversation)

    assert refused.status_code == 403
    detail = client.get(f"{CONVERSATIONS}/{conversation['id']}", headers=team["h"]["viewer"])
    assert detail.json()["messages"][-1]["action"]["status"] == "proposed"


def test_dismissed_action_cannot_be_applied_afterwards(client, team, llm):
    llm.replies = [reply("Décision ?", "create_decision", title="X", project_number=1)]
    conversation = _ask(client, team["h"]["lead"], "Note X")

    dismissed = _decide(client, team["h"]["lead"], conversation, apply=False)

    assert dismissed.json()["action"]["status"] == "dismissed"
    assert _decide(client, team["h"]["lead"], conversation).status_code == 409


def test_only_the_author_can_decide(client, team, llm):
    llm.replies = [reply("Décision ?", "create_decision", title="X", project_number=1)]
    conversation = _ask(client, team["h"]["lead"], "Note X")

    assert _decide(client, team["h"]["contributor"], conversation).status_code == 404


def test_message_without_action_cannot_be_decided(client, team, llm):
    llm.replies = [reply("Bonjour.")]
    conversation = _ask(client, team["h"]["lead"], "Salut")

    assert conversation["messages"][-1]["action"] is None
    assert _decide(client, team["h"]["lead"], conversation).status_code == 409


def test_invalid_proposal_is_dropped_but_the_answer_kept(client, team, llm):
    llm.replies = [reply("Voilà.", "create_project", title="")]
    headers = team["h"]["lead"]

    message = _ask(client, headers, "Crée un projet")["messages"][-1]

    assert (message["content"], message["action"]) == ("Voilà.", None)
