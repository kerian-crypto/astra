import json
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.ai.client import AIUnavailableError
from app.api.v1.ai import get_llm
from app.main import create_app

TODAY = "2026-10-01"


class FakeLLM:
    """Faux Ronda : enregistre les messages reçus et renvoie des réponses prévues."""

    def __init__(self) -> None:
        self.calls: list[dict] = []
        self.replies: list[str] = []
        self.fail = False

    def is_reachable(self) -> bool:
        return True

    def chat(self, messages, *, max_tokens, json_schema=None) -> str:
        self.calls.append({"messages": messages, "json_schema": json_schema})
        if self.fail:
            raise AIUnavailableError("Ronda est injoignable pour le moment.")
        return self.replies.pop(0)

    def prompt_text(self) -> str:
        return "\n".join(m["content"] for m in self.calls[-1]["messages"])


@pytest.fixture
def llm() -> FakeLLM:
    return FakeLLM()


@pytest.fixture
def client(llm) -> Iterator[TestClient]:
    app = create_app()
    app.dependency_overrides[get_llm] = lambda: llm
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_ai_disabled_when_not_configured(make_user, auth_headers):
    headers = auth_headers(make_user())
    # Sans surcharge, get_llm renvoie None (AI_BASE_URL absent) : service indisponible.
    with TestClient(create_app()) as plain_client:
        status = plain_client.get("/api/v1/ai/status", headers=headers).json()
        ask = plain_client.post("/api/v1/ai/ask", headers=headers, json={"question": "Salut"})

    assert status == {"enabled": False, "reachable": False, "model": None}
    assert ask.status_code == 503


def test_ask_uses_only_data_the_user_can_see(client, team, llm):
    client.post(
        f"/api/v1/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": "Négociation contrat Zephyr", "assignee_id": str(team["contributor"].id)},
    )
    llm.replies = ["Vous n'avez aucune tâche liée à Zephyr."]

    response = client.post(
        "/api/v1/ai/ask",
        headers=team["h"]["outsider"],
        json={"question": "Donne-moi les informations du contrat Zephyr"},
        params={"today": TODAY},
    )

    assert response.status_code == 200
    assert "Zephyr" not in llm.prompt_text().split("Question :")[0]
    assert response.json()["sources"] == []


def test_ask_includes_my_work_and_returns_cited_sources(client, team, llm):
    client.post(
        f"/api/v1/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={
            "title": "Maquettes Zephyr",
            "assignee_id": str(team["contributor"].id),
            "due_date": TODAY,
        },
    )
    llm.replies = ["Votre priorité du jour : les maquettes [1]."]

    response = client.post(
        "/api/v1/ai/ask",
        headers=team["h"]["contributor"],
        json={
            "question": "Quels sont mes travaux prioritaires aujourd'hui ?",
            "history": [
                {"role": "user", "content": "Bonjour"},
                {"role": "assistant", "content": "Bonjour !"},
            ],
        },
        params={"today": TODAY},
    ).json()

    prompt = llm.prompt_text()
    assert "Mes tâches du jour" in prompt
    assert "[1] Maquettes Zephyr" in prompt
    assert [m["role"] for m in llm.calls[-1]["messages"]] == ["system", "user", "assistant", "user"]
    assert response["sources"] == [
        {
            "number": 1,
            "type": "work",
            "id": response["sources"][0]["id"],
            "title": "Maquettes Zephyr",
        }
    ]


def test_plan_proposal_then_human_validation_creates_project(client, make_user, auth_headers, llm):
    from app.models.enums import AccessLevel

    manager = make_user(AccessLevel.MANAGER)
    headers = auth_headers(manager)
    llm.replies = [
        json.dumps(
            {
                "name": "Plateforme de formations",
                "objective": "Gérer les formations en ligne",
                "description": "Plateforme web",
                "phases": [
                    {
                        "name": "Analyse",
                        "description": "Besoins",
                        "tasks": [
                            {
                                "title": "Interviews",
                                "description": "5 formateurs",
                                "priority": "high",
                            }
                        ],
                    },
                    {"name": "Backend", "description": "API", "tasks": []},
                ],
                "deliverables": ["Cahier des charges"],
                "risks": ["Adoption"],
                "required_skills": ["FastAPI"],
                "estimated_workload_days": 40,
            }
        )
    ]

    proposal = client.post(
        "/api/v1/ai/plan",
        headers=headers,
        json={"idea": "Nous devons créer une plateforme web de gestion des formations."},
    )
    assert proposal.status_code == 200, proposal.text
    body = proposal.json()
    assert llm.calls[-1]["json_schema"]["title"] == "PlanDraft"
    # Rien n'est créé tant que l'humain n'a pas validé.
    assert client.get("/api/v1/projects", headers=headers).json() == []

    created = client.post("/api/v1/projects/from-plan", headers=headers, json=body["plan"])
    assert created.status_code == 201, created.text
    project_id = created.json()["id"]
    tasks = client.get(f"/api/v1/projects/{project_id}/tasks", headers=headers).json()
    assert [t["title"] for t in tasks] == ["Interviews"]
    assert body["risks"] == ["Adoption"]


def test_plan_from_plain_member_cannot_be_applied(client, make_user, auth_headers):
    response = client.post(
        "/api/v1/projects/from-plan", headers=auth_headers(make_user()), json={"name": "P"}
    )

    assert response.status_code == 403


def test_invalid_model_output_returns_502(client, make_user, auth_headers, llm):
    llm.replies = ['{"name": "incomplet"}']

    response = client.post(
        "/api/v1/ai/plan",
        headers=auth_headers(make_user()),
        json={"idea": "Une idée suffisamment longue"},
    )

    assert response.status_code == 502


def test_unreachable_model_returns_503(client, make_user, auth_headers, llm):
    llm.fail = True

    response = client.post(
        "/api/v1/ai/ask", headers=auth_headers(make_user()), json={"question": "Bonjour"}
    )

    assert response.status_code == 503


def test_meeting_summary_maps_assignees_to_participants(client, team, llm):
    meeting = client.post(
        "/api/v1/meetings",
        headers=team["h"]["lead"],
        json={
            "title": "Kick-off",
            "scheduled_at": "2026-10-01T09:00:00+00:00",
            "project_id": team["project"]["id"],
            "participant_ids": [str(team["contributor"].id)],
        },
    ).json()
    url = f"/api/v1/ai/meetings/{meeting['id']}/summary"
    no_minutes = client.post(url, headers=team["h"]["lead"])
    client.patch(
        f"/api/v1/meetings/{meeting['id']}",
        headers=team["h"]["lead"],
        json={"minutes": "On part sur FastAPI. Le contributeur fait l'API pour le 15/10."},
    )
    participants = client.get(
        f"/api/v1/meetings/{meeting['id']}", headers=team["h"]["lead"]
    ).json()["participants"]
    contributor_number = [p["id"] for p in participants].index(str(team["contributor"].id)) + 1
    llm.replies = [
        json.dumps(
            {
                "summary": "Choix technique et répartition.",
                "decisions": [{"title": "Adopter FastAPI", "description": "Backend"}],
                "open_questions": [],
                "tasks": [
                    {
                        "title": "Écrire l'API",
                        "description": "",
                        "assignee_number": contributor_number,
                        "due_date": "2026-10-15",
                    },
                    {
                        "title": "Doc",
                        "description": "",
                        "assignee_number": 99,
                        "due_date": "bientôt",
                    },
                ],
                "risks": [],
            }
        )
    ]

    summary = client.post(url, headers=team["h"]["lead"]).json()
    outsider = client.post(url, headers=team["h"]["outsider"])

    assert no_minutes.status_code == 400
    api_task, doc_task = summary["tasks"]
    assert api_task["assignee_id"] == str(team["contributor"].id)
    assert api_task["due_date"] == "2026-10-15"
    assert (doc_task["assignee_id"], doc_task["due_date"]) == (None, None)
    assert "<compte_rendu>" in llm.prompt_text()
    assert outsider.status_code == 404


def test_ai_is_rate_limited_per_user(client, make_user, auth_headers, llm):
    from app.api.v1.ai import AI_REQUESTS_PER_WINDOW

    headers = auth_headers(make_user())
    llm.replies = ["ok"] * AI_REQUESTS_PER_WINDOW
    for _ in range(AI_REQUESTS_PER_WINDOW):
        client.post("/api/v1/ai/ask", headers=headers, json={"question": "?"})

    response = client.post("/api/v1/ai/ask", headers=headers, json={"question": "?"})

    assert response.status_code == 429


def test_health_report_is_based_on_visible_indicators(client, team, llm):
    llm.replies = ["- Tout va bien."]

    response = client.get(
        "/api/v1/ai/health-report", headers=team["h"]["viewer"], params={"today": TODAY}
    )

    assert response.json() == {"report": "- Tout va bien."}
    assert "<indicateurs>" in llm.prompt_text()
