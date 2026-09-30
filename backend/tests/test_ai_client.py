import httpx
import pytest

from app.ai import client as client_module
from app.ai.client import AIResponseError, AIUnavailableError, LlamaServerClient

URL = "http://ronda.test:8080"


def make_client(**kwargs) -> LlamaServerClient:
    return LlamaServerClient(URL, "ronda", 30, **kwargs)


def fake_post(monkeypatch, handler):
    calls = []

    def post(url, json, timeout, headers=None):
        calls.append({"url": url, "json": json, "timeout": timeout, "headers": headers or {}})
        request = httpx.Request("POST", url)
        response = handler(request)
        response.request = request
        return response

    monkeypatch.setattr(client_module.httpx, "post", post)
    return calls


def completion(content: str) -> httpx.Response:
    return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})


def test_sends_openai_compatible_request_with_schema_and_no_thinking(monkeypatch):
    calls = fake_post(monkeypatch, lambda request: completion('{"a": 1}'))

    result = make_client().chat(
        [{"role": "user", "content": "x"}], max_tokens=50, json_schema={"type": "object"}
    )

    (call,) = calls
    assert result == '{"a": 1}'
    assert call["url"] == f"{URL}/v1/chat/completions"
    assert call["json"]["max_tokens"] == 50
    assert call["json"]["chat_template_kwargs"] == {"enable_thinking": False}
    assert call["json"]["response_format"]["json_schema"]["schema"] == {"type": "object"}


def test_api_key_is_sent_when_configured(monkeypatch):
    calls = fake_post(monkeypatch, lambda request: completion("ok"))

    make_client(api_key="secret-ronda-key").chat([], max_tokens=10)
    make_client().chat([], max_tokens=10)

    assert calls[0]["headers"] == {"Authorization": "Bearer secret-ronda-key"}
    assert "Authorization" not in calls[1]["headers"]


def test_thinking_can_be_enabled(monkeypatch):
    calls = fake_post(monkeypatch, lambda request: completion("ok"))

    make_client(enable_thinking=True).chat([], max_tokens=10)

    assert calls[0]["json"]["chat_template_kwargs"] == {"enable_thinking": True}
    assert "response_format" not in calls[0]["json"]


def test_strips_leftover_thinking_blocks(monkeypatch):
    fake_post(monkeypatch, lambda request: completion("<think>brouillon</think>\nRéponse"))

    assert make_client().chat([], max_tokens=10) == "Réponse"


@pytest.mark.parametrize(
    ("handler", "error"),
    [
        (lambda request: httpx.Response(500, request=request), AIUnavailableError),
        (lambda request: httpx.Response(200, json={"choices": []}), AIResponseError),
    ],
)
def test_maps_server_failures(monkeypatch, handler, error):
    fake_post(monkeypatch, handler)

    with pytest.raises(error):
        make_client().chat([], max_tokens=10)


def test_timeout_is_reported_as_unavailable(monkeypatch):
    def raise_timeout(request):
        raise httpx.ReadTimeout("lent", request=request)

    fake_post(monkeypatch, raise_timeout)

    with pytest.raises(AIUnavailableError, match="trop de temps"):
        make_client().chat([], max_tokens=10)


def test_busy_model_is_reported_without_waiting_forever(monkeypatch):
    llm = make_client()
    monkeypatch.setattr(client_module, "QUEUE_WAIT_SECONDS", 0)
    llm._slot.acquire()

    with pytest.raises(AIUnavailableError, match="occupée"):
        llm.chat([], max_tokens=10)


def test_reachability_check(monkeypatch):
    monkeypatch.setattr(client_module.httpx, "get", lambda url, timeout: httpx.Response(200))
    assert make_client().is_reachable() is True

    def down(url, timeout):
        raise httpx.ConnectError("refusé")

    monkeypatch.setattr(client_module.httpx, "get", down)
    assert make_client().is_reachable() is False
