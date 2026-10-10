"""Messagerie client, tickets, notifications et push (§24-25, §34-35, §49)."""

import io

from sqlalchemy import select

from app.models import Notification
from tests.client_fixtures import API


def _start(client, world, name="a", **extra):
    response = client.post(
        f"{API}/client/conversations",
        headers=world[name]["h"],
        json={"subject": "Question", "body": "Bonjour Astra", **extra},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_client_message_reaches_hub_and_reply_reaches_client(client, client_world, db):
    conversation = _start(client, client_world)
    mh = client_world["mh"]

    hub_list = client.get(f"{API}/clients/conversations", headers=mh).json()
    reply = client.post(
        f"{API}/clients/conversations/{conversation['id']}/messages",
        headers=mh,
        data={"body": "Bonjour, nous regardons."},
    )
    client_view = client.get(
        f"{API}/client/conversations/{conversation['id']}", headers=client_world["a"]["h"]
    ).json()
    messages = client.get(
        f"{API}/client/conversations/{conversation['id']}/messages",
        headers=client_world["a"]["h"],
    ).json()

    assert [c["id"] for c in hub_list] == [conversation["id"]]
    assert hub_list[0]["company_name"] == "Entreprise A"
    assert reply.status_code == 201
    assert client_view["unread_count"] == 1
    assert [m["from_astra"] for m in messages] == [False, True]
    assert messages[0]["is_mine"] is True
    assert "client_message" in db.scalars(select(Notification.kind)).all()


def test_mark_read_resets_unread(client, client_world):
    conversation = _start(client, client_world)
    client.post(
        f"{API}/clients/conversations/{conversation['id']}/messages",
        headers=client_world["mh"],
        data={"body": "Réponse"},
    )
    a = client_world["a"]["h"]

    client.post(f"{API}/client/conversations/{conversation['id']}/read", headers=a)

    view = client.get(f"{API}/client/conversations/{conversation['id']}", headers=a).json()
    assert view["unread_count"] == 0


def test_client_b_cannot_read_or_post_in_conversation_a(client, client_world):
    conversation = _start(client, client_world)
    b = client_world["b"]["h"]

    assert client.get(f"{API}/client/conversations", headers=b).json() == []
    assert (
        client.get(
            f"{API}/client/conversations/{conversation['id']}/messages", headers=b
        ).status_code
        == 404
    )
    assert (
        client.post(
            f"{API}/client/conversations/{conversation['id']}/messages",
            headers=b,
            data={"body": "intrus"},
        ).status_code
        == 404
    )


def test_cannot_start_conversation_on_foreign_project(client, client_world):
    response = client.post(
        f"{API}/client/conversations",
        headers=client_world["a"]["h"],
        json={"subject": "x", "body": "y", "project_id": client_world["b"]["project"]["id"]},
    )

    assert response.status_code == 404


def test_project_conversation_and_attachment(client, client_world):
    a = client_world["a"]
    conversation = client.post(
        f"{API}/client/projects/{a['project']['id']}/conversation", headers=a["h"]
    ).json()

    message = client.post(
        f"{API}/client/conversations/{conversation['id']}/messages",
        headers=a["h"],
        data={"body": ""},
        files={"file": ("photo.png", io.BytesIO(b"\x89PNG\r\n\x1a\nxxxx"), "image/png")},
    )
    download = client.get(
        f"{API}/client/conversations/{conversation['id']}/messages/{message.json()['id']}/file",
        headers=a["h"],
    )
    again = client.post(
        f"{API}/client/projects/{a['project']['id']}/conversation", headers=a["h"]
    ).json()

    assert conversation["kind"] == "project"
    assert message.status_code == 201, message.text
    assert message.json()["file"]["name"] == "photo.png"
    assert download.status_code == 200
    assert again["id"] == conversation["id"]


def test_hub_member_sees_only_conversations_of_own_projects(
    client, client_world, make_user, auth_headers
):
    _start(client, client_world)
    member = auth_headers(make_user())

    assert client.get(f"{API}/clients/conversations", headers=member).json() == []


def test_member_without_permission_cannot_message(client, client_world, make_client_account):
    reader = make_client_account(
        client_world["mh"], client_world["a"]["company"]["id"], permissions=["view_project"]
    )

    response = client.post(
        f"{API}/client/conversations", headers=reader["h"], json={"subject": "x", "body": "y"}
    )

    assert response.status_code == 403


# ---------- Tickets ----------


def test_ticket_lifecycle(client, client_world, db):
    a = client_world["a"]
    ticket = client.post(
        f"{API}/client/tickets",
        headers=a["h"],
        json={"type": "technical", "subject": "Problème sur le site", "description": "Erreur 500"},
    )
    assert ticket.status_code == 201, ticket.text
    body = ticket.json()
    assert body["number"].startswith("SUP-")
    assert body["status"] == "new"
    assert body["conversation_id"]
    assert "client_ticket" in db.scalars(select(Notification.kind)).all()

    updated = client.patch(
        f"{API}/clients/tickets/{body['id']}",
        headers=client_world["mh"],
        json={"status": "waiting_client", "assignee_id": str(client_world["manager"].id)},
    )
    dashboard = client.get(f"{API}/client/dashboard", headers=a["h"]).json()
    notifications = client.get(f"{API}/client/notifications", headers=a["h"]).json()

    assert updated.json()["status"] == "waiting_client"
    assert updated.json()["assignee_name"] == client_world["manager"].full_name
    assert any(action["kind"] == "ticket_reply" for action in dashboard["actions"])
    assert any(n["kind"] == "ticket_updated" for n in notifications)


def test_ticket_numbers_are_sequential_and_isolated(client, client_world):
    payload = {"type": "question", "subject": "Q", "description": "D"}
    first = client.post(
        f"{API}/client/tickets", headers=client_world["a"]["h"], json=payload
    ).json()
    second = client.post(
        f"{API}/client/tickets", headers=client_world["b"]["h"], json=payload
    ).json()

    assert int(second["number"].rsplit("-", 1)[1]) == int(first["number"].rsplit("-", 1)[1]) + 1
    assert (
        client.get(
            f"{API}/client/tickets/{first['id']}", headers=client_world["b"]["h"]
        ).status_code
        == 404
    )
    assert [
        t["id"] for t in client.get(f"{API}/client/tickets", headers=client_world["b"]["h"]).json()
    ] == [second["id"]]


# ---------- Notifications et push ----------


def test_client_notifications_are_pushed_to_client_devices_only(client, client_world, pushes):
    a = client_world["a"]
    client.put(
        f"{API}/client/devices", headers=a["h"], json={"token": "tok_A", "platform": "android"}
    )
    conversation = _start(client, client_world)

    client.post(
        f"{API}/clients/conversations/{conversation['id']}/messages",
        headers=client_world["mh"],
        data={"body": "Réponse"},
    )

    client_pushes = [m for ids, m in pushes.sent if m.audience == "client"]
    assert client_pushes and client_pushes[-1].type == "new_message"
    assert all(
        a["account"]["id"] in {str(i) for i in ids}
        for ids, m in pushes.sent
        if m.audience == "client"
    )


def test_notifications_read_flow(client, client_world):
    conversation = _start(client, client_world)
    client.post(
        f"{API}/clients/conversations/{conversation['id']}/messages",
        headers=client_world["mh"],
        data={"body": "Réponse"},
    )
    a = client_world["a"]["h"]

    count = client.get(f"{API}/client/notifications/unread-count", headers=a).json()["count"]
    notification = client.get(f"{API}/client/notifications", headers=a).json()[0]
    client.post(f"{API}/client/notifications/{notification['id']}/read", headers=a)
    foreign = client.post(
        f"{API}/client/notifications/{notification['id']}/read", headers=client_world["b"]["h"]
    )

    assert count >= 1
    assert foreign.status_code == 404
    assert notification["entity_type"] == "client_conversation"


# ---------- Temps réel ----------


def test_client_websocket_receives_astra_reply(client, client_world):
    conversation = _start(client, client_world)

    with client.websocket_connect(f"{API}/client/ws") as ws:
        ws.send_json({"type": "auth", "token": client_world["a"]["tokens"]["access_token"]})
        assert ws.receive_json()["type"] == "ready"
        client.post(
            f"{API}/clients/conversations/{conversation['id']}/messages",
            headers=client_world["mh"],
            data={"body": "En direct"},
        )
        events = [ws.receive_json(), ws.receive_json()]

    by_type = {e["type"]: e for e in events}
    assert by_type["message.created"]["message"]["body"] == "En direct"
    assert by_type["notification.created"]["notification"]["kind"] == "new_message"


def test_client_websocket_refuses_member_token(client, client_world, login):
    with client.websocket_connect(f"{API}/client/ws") as ws:
        ws.send_json({"type": "auth", "token": login(client_world["manager"])["access_token"]})
        message = ws.receive()

    assert message["type"] == "websocket.close"
    assert message["code"] == 4001


def test_hub_websocket_refuses_client_token(client, client_world):
    with client.websocket_connect(f"{API}/ws") as ws:
        ws.send_json({"type": "auth", "token": client_world["a"]["tokens"]["access_token"]})
        message = ws.receive()

    assert message["code"] == 4001
