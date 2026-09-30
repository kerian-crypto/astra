"""Conversations ASTRA AI persistées par compte, générées en arrière-plan."""

from collections.abc import Callable, Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.v1.ai import get_llm
from app.main import create_app
from app.models import AIConversation, AIMessage
from app.models.enums import AIMessageStatus, AIRole
from tests.test_ai import TODAY, FakeLLM

BASE = "/api/v1/ai/conversations"


class InlineJobs:
    """Exécute la génération immédiatement (déterministe pour les tests)."""

    def submit(self, fn: Callable, *args) -> None:
        fn(*args)


class DeferredJobs:
    """Garde les générations en attente : simule un membre qui quitte l'écran."""

    def __init__(self) -> None:
        self.pending: list[tuple[Callable, tuple]] = []

    def submit(self, fn: Callable, *args) -> None:
        self.pending.append((fn, args))

    def run_all(self) -> None:
        while self.pending:
            fn, args = self.pending.pop(0)
            fn(*args)


@pytest.fixture
def llm() -> FakeLLM:
    return FakeLLM()


@pytest.fixture
def jobs() -> InlineJobs:
    return InlineJobs()


@pytest.fixture
def client(llm, jobs) -> Iterator[TestClient]:
    app = create_app()
    app.dependency_overrides[get_llm] = lambda: llm
    with TestClient(app) as test_client:
        app.state.ai_jobs = jobs
        yield test_client
    app.dependency_overrides.clear()


def _ask(client, headers, question, conversation_id=None):
    url = f"{BASE}/{conversation_id}/messages" if conversation_id else BASE
    return client.post(url, headers=headers, json={"question": question}, params={"today": TODAY})


def test_first_question_creates_a_persisted_conversation(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())
    llm.replies = ["Bonjour, je suis Ronda."]

    response = _ask(client, headers, "Présente-toi en une phrase")

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["title"] == "Présente-toi en une phrase"
    assert [(m["role"], m["status"]) for m in body["messages"]] == [
        ("user", "done"),
        ("assistant", "done"),
    ]
    assert body["messages"][1]["content"] == "Bonjour, je suis Ronda."

    detail = client.get(f"{BASE}/{body['id']}", headers=headers).json()
    assert detail["messages"] == body["messages"]
    listed = client.get(BASE, headers=headers).json()
    assert [(c["id"], c["is_pending"]) for c in listed] == [(body["id"], False)]


def test_follow_up_questions_send_the_stored_history_to_ronda(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())
    llm.replies = ["Première réponse.", "Deuxième réponse."]
    conversation = _ask(client, headers, "Première question").json()

    response = _ask(client, headers, "Et ensuite ?", conversation["id"])

    assert response.status_code == 201
    assert len(response.json()["messages"]) == 4
    roles = [m["role"] for m in llm.calls[-1]["messages"]]
    contents = [m["content"] for m in llm.calls[-1]["messages"]]
    assert roles == ["system", "user", "assistant", "user"]
    assert contents[1:3] == ["Première question", "Première réponse."]


def test_conversations_are_private_to_each_account(client, make_user, auth_headers, llm):
    owner, other = auth_headers(make_user()), auth_headers(make_user())
    llm.replies = ["Réponse privée."]
    conversation = _ask(client, owner, "Question privée").json()

    assert client.get(BASE, headers=other).json() == []
    assert client.get(f"{BASE}/{conversation['id']}", headers=other).status_code == 404
    assert _ask(client, other, "Intrusion", conversation["id"]).status_code == 404
    assert client.delete(f"{BASE}/{conversation['id']}", headers=other).status_code == 404


@pytest.mark.parametrize("jobs", [DeferredJobs()])
def test_reply_keeps_generating_after_leaving_the_conversation(
    client, make_user, auth_headers, llm, jobs
):
    headers = auth_headers(make_user())
    llm.replies = ["Réponse longue terminée.", "Autre réponse."]

    first = _ask(client, headers, "Question longue").json()
    assert first["messages"][-1]["status"] == "pending"
    # Le membre ouvre une nouvelle conversation pendant que Ronda travaille.
    second = _ask(client, headers, "Nouvelle conversation").json()
    listed = {c["id"]: c["is_pending"] for c in client.get(BASE, headers=headers).json()}
    assert listed == {first["id"]: True, second["id"]: True}

    jobs.run_all()

    reply = client.get(f"{BASE}/{first['id']}", headers=headers).json()["messages"][-1]
    assert (reply["status"], reply["content"]) == ("done", "Réponse longue terminée.")
    assert not any(c["is_pending"] for c in client.get(BASE, headers=headers).json())


@pytest.mark.parametrize("jobs", [DeferredJobs()])
def test_only_one_pending_reply_per_conversation(client, make_user, auth_headers, llm, jobs):
    headers = auth_headers(make_user())
    conversation = _ask(client, headers, "Question").json()

    response = _ask(client, headers, "Encore une", conversation["id"])

    assert response.status_code == 409


def test_failed_reply_is_stored_and_left_out_of_the_history(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())
    llm.fail = True
    conversation = _ask(client, headers, "Question sans réponse").json()
    failed = conversation["messages"][-1]
    assert failed["status"] == "failed"
    assert failed["content"] == "Ronda est injoignable pour le moment."

    llm.fail = False
    llm.replies = ["Me revoilà."]
    _ask(client, headers, "Tu es là ?", conversation["id"])

    assert [m["role"] for m in llm.calls[-1]["messages"]] == ["system", "user"]
    assert "Question sans réponse" not in llm.prompt_text()


@pytest.mark.parametrize("jobs", [DeferredJobs()])
def test_deleting_a_conversation_during_generation(client, make_user, auth_headers, llm, jobs):
    headers = auth_headers(make_user())
    llm.replies = ["Trop tard."]
    conversation = _ask(client, headers, "Question").json()

    assert client.delete(f"{BASE}/{conversation['id']}", headers=headers).status_code == 204
    jobs.run_all()  # ne doit pas échouer

    assert client.get(f"{BASE}/{conversation['id']}", headers=headers).status_code == 404
    assert client.get(BASE, headers=headers).json() == []


def test_unexpected_errors_are_stored_as_failed(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())

    def boom(*_, **__):
        raise RuntimeError("panne")

    llm.chat = boom

    reply = _ask(client, headers, "Question").json()["messages"][-1]

    assert reply["status"] == "failed"
    assert "panne" not in reply["content"]


def test_replies_interrupted_by_a_restart_are_marked_failed(db, make_user):
    user = make_user()
    conversation = AIConversation(user_id=user.id, title="Coupée")
    conversation.messages = [
        AIMessage(role=AIRole.USER, content="Question", status=AIMessageStatus.DONE),
        AIMessage(role=AIRole.ASSISTANT, content="", status=AIMessageStatus.PENDING),
    ]
    db.add(conversation)
    db.commit()

    with TestClient(create_app()):
        pass

    db.refresh(conversation.messages[1])
    assert conversation.messages[1].status == AIMessageStatus.FAILED
    assert conversation.messages[1].content


def test_nothing_is_stored_when_ai_is_disabled(make_user, auth_headers):
    headers = auth_headers(make_user())
    with TestClient(create_app()) as plain_client:
        response = _ask(plain_client, headers, "Salut")
        assert response.status_code == 503
        assert plain_client.get(BASE, headers=headers).json() == []


def test_question_is_validated(client, make_user, auth_headers):
    headers = auth_headers(make_user())

    assert _ask(client, headers, "").status_code == 422
    assert _ask(client, headers, "x" * 2_001).status_code == 422


def test_long_first_question_gives_a_short_title(client, make_user, auth_headers, llm):
    headers = auth_headers(make_user())
    llm.replies = ["Ok."]

    title = _ask(client, headers, "mot " * 100).json()["title"]

    assert len(title) <= 80
    assert title.endswith("…")


def test_finished_reply_is_pushed_to_its_owner(client, make_user, auth_headers, llm, pushes):
    owner = make_user()
    llm.replies = ["Voici le point."]

    conversation = _ask(client, auth_headers(owner), "Où en est MarketCM ?").json()

    (push,) = pushes.to(owner)
    assert (push.type, push.title) == ("ai_reply", "Ronda a répondu")
    assert (push.entity_type, str(push.entity_id)) == ("ai_conversation", conversation["id"])
