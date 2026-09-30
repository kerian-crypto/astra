"""Infrastructure push : appareils, client FCM, répartiteur, déclenchement au commit."""

import json
import uuid

import httpx
import pytest
from sqlalchemy import select

from app.db.session import get_session_factory
from app.models import DeviceToken, Notification
from app.models.enums import DevicePlatform, NotificationKind
from app.push import hooks as push_hooks
from app.push.dispatcher import PushDispatcher
from app.push.fcm import FcmSender, FirebaseConfigError, SendResult, build_payload
from app.push.message import PushChannel, PushMessage
from app.services import device_service

DEVICES = "/api/v1/devices"
TOKEN = "fcm-token_abc:123"


def _tokens(db, user) -> list[str]:
    db.expire_all()
    return list(db.scalars(select(DeviceToken.token).where(DeviceToken.user_id == user.id)))


def _message(**fields) -> PushMessage:
    defaults = {
        "title": "Titre",
        "body": "Corps",
        "type": "task_assigned",
        "entity_type": "task",
        "entity_id": uuid.UUID(int=1),
    }
    return PushMessage(**(defaults | fields))


# ---------- API des appareils ----------


def test_member_registers_device_idempotently(client, db, make_user, auth_headers):
    member = make_user()
    headers = auth_headers(member)

    for _ in range(2):
        response = client.put(
            DEVICES, headers=headers, json={"token": TOKEN, "platform": "android"}
        )
        assert response.status_code == 204, response.text

    assert _tokens(db, member) == [TOKEN]


def test_token_moves_to_the_account_that_registers_it_last(client, db, make_user, auth_headers):
    first, second = make_user(), make_user()
    body = {"token": TOKEN, "platform": "android"}

    client.put(DEVICES, headers=auth_headers(first), json=body)
    client.put(DEVICES, headers=auth_headers(second), json=body)

    assert _tokens(db, first) == []
    assert _tokens(db, second) == [TOKEN]


def test_oldest_devices_are_forgotten_beyond_the_limit(client, db, make_user, auth_headers):
    member = make_user()
    headers = auth_headers(member)

    for index in range(device_service.MAX_DEVICES_PER_USER + 2):
        client.put(DEVICES, headers=headers, json={"token": f"t{index}", "platform": "ios"})

    remaining = _tokens(db, member)
    assert len(remaining) == device_service.MAX_DEVICES_PER_USER
    assert "t0" not in remaining and "t1" not in remaining


def test_unregister_only_removes_own_token(client, db, make_user, auth_headers):
    owner, other = make_user(), make_user()
    client.put(DEVICES, headers=auth_headers(owner), json={"token": TOKEN, "platform": "android"})

    by_other = client.post(
        f"{DEVICES}/unregister", headers=auth_headers(other), json={"token": TOKEN}
    )
    assert by_other.status_code == 204
    assert _tokens(db, owner) == [TOKEN]

    client.post(f"{DEVICES}/unregister", headers=auth_headers(owner), json={"token": TOKEN})
    assert _tokens(db, owner) == []


@pytest.mark.parametrize(
    "body",
    [
        {"token": "", "platform": "android"},
        {"token": "a b", "platform": "android"},
        {"token": "x" * 5000, "platform": "android"},
        {"token": TOKEN, "platform": "windows"},
    ],
)
def test_register_rejects_invalid_input(client, make_user, auth_headers, body):
    response = client.put(DEVICES, headers=auth_headers(make_user()), json=body)

    assert response.status_code == 422


def test_devices_require_authentication(client):
    response = client.put(DEVICES, json={"token": TOKEN, "platform": "android"})

    assert response.status_code == 401


# ---------- Client FCM ----------


class StaticTokens:
    def access_token(self) -> str:
        return "oauth-token"


def _sender(handler) -> tuple[FcmSender, list[httpx.Request]]:
    requests: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return handler(request)

    http = httpx.Client(transport=httpx.MockTransport(record))
    return FcmSender("astra-test", StaticTokens(), http), requests


def _fcm_error(status: int, code: str, message: str = "") -> httpx.Response:
    detail = {"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode": code}
    return httpx.Response(
        status, json={"error": {"code": status, "message": message, "details": [detail]}}
    )


def test_fcm_sends_notification_and_navigation_data():
    sender, requests = _sender(lambda _: httpx.Response(200, json={"name": "m/1"}))
    notification_id = uuid.uuid4()

    result = sender.send(TOKEN, _message(notification_id=notification_id))

    assert result == SendResult.SENT
    request = requests[0]
    assert request.url.path == "/v1/projects/astra-test/messages:send"
    assert request.headers["Authorization"] == "Bearer oauth-token"
    message = json.loads(request.content)["message"]
    assert message["token"] == TOKEN
    assert message["notification"] == {"title": "Titre", "body": "Corps"}
    assert message["data"] == {
        "type": "task_assigned",
        "entity_type": "task",
        "entity_id": str(uuid.UUID(int=1)),
        "notification_id": str(notification_id),
    }
    assert message["android"]["notification"]["channel_id"] == "activity"


def test_payload_omits_empty_body_and_uses_message_channel():
    message = PushMessage(
        title="T",
        body=None,
        type="message",
        entity_type="channel",
        entity_id=uuid.UUID(int=2),
        channel=PushChannel.MESSAGES,
    )

    payload = build_payload(TOKEN, message)

    assert payload["message"]["notification"] == {"title": "T"}
    assert payload["message"]["android"]["notification"]["channel_id"] == "messages"


@pytest.mark.parametrize(
    ("response", "expected"),
    [
        (_fcm_error(404, "UNREGISTERED"), SendResult.INVALID_TOKEN),
        (_fcm_error(403, "SENDER_ID_MISMATCH"), SendResult.INVALID_TOKEN),
        (
            _fcm_error(400, "INVALID_ARGUMENT", "The registration token is not a valid FCM token"),
            SendResult.INVALID_TOKEN,
        ),
        (_fcm_error(400, "INVALID_ARGUMENT", "Invalid JSON payload"), SendResult.FAILED),
        (_fcm_error(503, "UNAVAILABLE"), SendResult.FAILED),
        (httpx.Response(500, text="oops"), SendResult.FAILED),
    ],
)
def test_fcm_classifies_errors(response, expected):
    sender, _ = _sender(lambda _: response)

    assert sender.send(TOKEN, _message()) == expected


def test_fcm_network_error_is_a_failure_not_a_crash():
    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("réseau coupé", request=request)

    sender, _ = _sender(fail)

    assert sender.send(TOKEN, _message()) == SendResult.FAILED


def test_service_account_file_must_exist_and_name_a_project(tmp_path):
    with pytest.raises(FirebaseConfigError):
        FcmSender.from_service_account_file(str(tmp_path / "absent.json"))

    broken = tmp_path / "broken.json"
    broken.write_text("{pas du json", encoding="utf-8")
    with pytest.raises(FirebaseConfigError):
        FcmSender.from_service_account_file(str(broken))


# ---------- Répartiteur ----------


class ScriptedSender:
    def __init__(self, results: dict[str, SendResult]) -> None:
        self.results = results
        self.sent: list[str] = []

    def send(self, token: str, message: PushMessage) -> SendResult:
        self.sent.append(token)
        return self.results.get(token, SendResult.SENT)

    def close(self) -> None:
        pass


def test_dispatcher_sends_to_active_members_and_forgets_dead_tokens(db, make_user):
    alice, bob, gone = make_user(), make_user(), make_user()
    for user, token in ((alice, "alice-phone"), (alice, "alice-old"), (bob, "bob"), (gone, "g")):
        device_service.register(db, user, token, DevicePlatform.ANDROID)
    gone.is_active = False
    db.commit()
    sender = ScriptedSender({"alice-old": SendResult.INVALID_TOKEN})
    dispatcher = PushDispatcher(get_session_factory(), sender)

    sent = dispatcher.deliver({alice.id, bob.id, gone.id}, _message())

    assert sent == 2
    assert sorted(sender.sent) == ["alice-old", "alice-phone", "bob"]
    assert _tokens(db, alice) == ["alice-phone"]


# ---------- Déclenchement au commit ----------


def test_notifications_and_queued_pushes_leave_only_after_commit(db, make_user, pushes):
    member = make_user()
    db.add(
        Notification(
            user_id=member.id,
            kind=NotificationKind.TASK_ASSIGNED,
            title="Nouvelle tâche",
            entity_type="task",
            entity_id=uuid.uuid4(),
        )
    )
    push_hooks.enqueue(db, {member.id}, _message(type="message"))
    db.flush()
    assert pushes.sent == []

    db.commit()

    assert pushes.types_to(member) == ["task_assigned", "message"]
    assert pushes.to(member)[0].notification_id is not None


def test_rollback_cancels_pending_pushes(db, make_user, pushes):
    member = make_user()
    db.execute(select(DeviceToken.id))  # transaction ouverte, comme dans un service
    push_hooks.enqueue(db, {member.id}, _message())

    db.rollback()
    db.commit()

    assert pushes.sent == []
