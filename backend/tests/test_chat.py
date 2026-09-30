import pytest

from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind

CHANNELS = "/api/v1/channels"


@pytest.fixture
def general(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


@pytest.fixture
def announcements(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="annonces", announcements_only=True)
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def post(client, headers, channel, body="Bonjour", **fields):
    return client.post(
        f"{CHANNELS}/{channel['id']}/messages", headers=headers, json={"body": body, **fields}
    )


# ---------- Canaux ----------


def test_public_channel_is_open_to_every_member(client, make_user, auth_headers, general):
    alice, bob = make_user(), make_user()

    sent = post(client, auth_headers(alice), general, "Salut tout le monde")
    messages = client.get(f"{CHANNELS}/{general['id']}/messages", headers=auth_headers(bob))

    assert sent.status_code == 201
    assert [m["body"] for m in messages.json()] == ["Salut tout le monde"]


def test_announcements_are_restricted_to_managers(client, make_user, auth_headers, announcements):
    member, manager = make_user(), make_user(AccessLevel.MANAGER)

    assert post(client, auth_headers(member), announcements).status_code == 403
    assert post(client, auth_headers(manager), announcements).status_code == 201
    listed = client.get(CHANNELS, headers=auth_headers(member)).json()
    assert listed[0]["can_post"] is False


def test_only_managers_create_public_channels(client, make_user, auth_headers):
    member, manager = make_user(), make_user(AccessLevel.MANAGER)
    body = {"kind": "public", "name": "design"}

    assert client.post(CHANNELS, headers=auth_headers(member), json=body).status_code == 403
    assert client.post(CHANNELS, headers=auth_headers(manager), json=body).status_code == 201


def test_channel_names_cannot_start_with_hash(client, make_user, auth_headers):
    response = client.post(
        CHANNELS,
        headers=auth_headers(make_user(AccessLevel.MANAGER)),
        json={"kind": "public", "name": "#design"},
    )

    assert response.status_code == 422


def test_private_group_is_hidden_from_non_members_even_admins(client, make_user, auth_headers):
    owner, friend = make_user(), make_user()
    admin, stranger = make_user(AccessLevel.ADMIN), make_user()
    group = client.post(
        CHANNELS,
        headers=auth_headers(owner),
        json={"kind": "private", "name": "Projet secret", "member_ids": [str(friend.id)]},
    ).json()
    post(client, auth_headers(owner), group, "confidentiel")

    assert {m["id"] for m in group["members"]} == {str(owner.id), str(friend.id)}
    assert post(client, auth_headers(friend), group).status_code == 201
    for outsider in (admin, stranger):
        url = f"{CHANNELS}/{group['id']}/messages"
        assert client.get(url, headers=auth_headers(outsider)).status_code == 404


def test_private_group_membership_management(client, make_user, auth_headers):
    owner, friend, newcomer = make_user(), make_user(), make_user()
    group = client.post(
        CHANNELS,
        headers=auth_headers(owner),
        json={"kind": "private", "name": "Groupe", "member_ids": [str(friend.id)]},
    ).json()
    url = f"{CHANNELS}/{group['id']}/members"

    by_friend = client.put(f"{url}/{newcomer.id}", headers=auth_headers(friend))
    by_owner = client.put(f"{url}/{newcomer.id}", headers=auth_headers(owner))
    newcomer_leaves = client.delete(f"{url}/{newcomer.id}", headers=auth_headers(newcomer))
    owner_leaves = client.delete(f"{url}/{owner.id}", headers=auth_headers(owner))

    assert by_friend.status_code == 403
    assert by_owner.status_code == 204
    assert newcomer_leaves.status_code == 204
    assert (
        client.get(f"{CHANNELS}/{group['id']}", headers=auth_headers(newcomer)).status_code == 404
    )
    assert owner_leaves.status_code == 409


def test_direct_conversation_is_unique_per_pair(client, make_user, auth_headers):
    alice, bob, carol = make_user(), make_user(), make_user()

    first = client.post(
        f"{CHANNELS}/direct", headers=auth_headers(alice), json={"user_id": str(bob.id)}
    ).json()
    second = client.post(
        f"{CHANNELS}/direct", headers=auth_headers(bob), json={"user_id": str(alice.id)}
    ).json()

    assert first["id"] == second["id"]
    assert first["display_name"] == bob.full_name
    assert second["display_name"] == alice.full_name
    assert client.get(f"{CHANNELS}/{first['id']}", headers=auth_headers(carol)).status_code == 404


def test_cannot_open_direct_conversation_with_self(client, make_user, auth_headers):
    alice = make_user()

    response = client.post(
        f"{CHANNELS}/direct", headers=auth_headers(alice), json={"user_id": str(alice.id)}
    )

    assert response.status_code == 400


def test_project_channel_follows_project_membership(client, team):
    url = f"/api/v1/projects/{team['project']['id']}/channel"

    channel = client.get(url, headers=team["h"]["viewer"]).json()
    again = client.get(url, headers=team["h"]["lead"]).json()

    assert channel["kind"] == "project"
    assert channel["name"] == "MarketCM V2"
    assert channel["id"] == again["id"]
    assert client.get(url, headers=team["h"]["outsider"]).status_code == 404
    messages_url = f"{CHANNELS}/{channel['id']}/messages"
    assert client.get(messages_url, headers=team["h"]["outsider"]).status_code == 404


# ---------- Messages ----------


def test_unread_counts_and_mark_read(client, make_user, auth_headers, general):
    alice, bob = make_user(), make_user()
    for text in ("1", "2", "3"):
        post(client, auth_headers(alice), general, text)

    def unread(user):
        (channel,) = client.get(CHANNELS, headers=auth_headers(user)).json()
        return channel["unread_count"]

    assert unread(bob) == 3
    assert unread(alice) == 0
    client.post(f"{CHANNELS}/{general['id']}/read", headers=auth_headers(bob))
    assert unread(bob) == 0


def test_messages_paginate_with_before_cursor(client, make_user, auth_headers, general):
    headers = auth_headers(make_user())
    for index in range(5):
        post(client, headers, general, f"m{index}")
    url = f"{CHANNELS}/{general['id']}/messages"

    page1 = client.get(url, headers=headers, params={"limit": 2}).json()
    page2 = client.get(
        url, headers=headers, params={"limit": 2, "before": page1[-1]["created_at"]}
    ).json()

    assert [m["body"] for m in page1] == ["m4", "m3"]
    assert [m["body"] for m in page2] == ["m2", "m1"]


def test_mention_notifies_only_people_who_can_read(client, team):
    channel = client.get(
        f"/api/v1/projects/{team['project']['id']}/channel", headers=team["h"]["lead"]
    ).json()

    sent = post(
        client,
        team["h"]["lead"],
        channel,
        "@contributeur @externe",
        mentioned_user_ids=[str(team["contributor"].id), str(team["outsider"].id)],
    ).json()
    contributor = client.get("/api/v1/notifications", headers=team["h"]["contributor"]).json()
    outsider = client.get("/api/v1/notifications", headers=team["h"]["outsider"]).json()

    assert sent["mentioned_user_ids"] == [str(team["contributor"].id)]
    assert [n["kind"] for n in contributor] == ["mention"]
    assert contributor[0]["entity_id"] == channel["id"]
    assert outsider == []


def test_reply_must_target_same_channel(client, make_user, auth_headers, general, db):
    headers = auth_headers(make_user())
    other = Channel(kind=ChannelKind.PUBLIC, name="autre")
    db.add(other)
    db.commit()
    parent = post(client, headers, general).json()

    ok = post(client, headers, general, "réponse", reply_to_id=parent["id"])
    ko = post(client, headers, {"id": str(other.id)}, "réponse", reply_to_id=parent["id"])

    assert ok.status_code == 201
    assert ko.status_code == 400


def test_edit_and_delete_by_author_only(client, make_user, auth_headers, general):
    author, other = make_user(), make_user()
    message = post(client, auth_headers(author), general, "brouillon").json()
    url = f"/api/v1/messages/{message['id']}"

    forbidden = client.patch(url, headers=auth_headers(other), json={"body": "piraté"})
    edited = client.patch(url, headers=auth_headers(author), json={"body": "version finale"})
    deleted = client.delete(url, headers=auth_headers(author))
    listed = client.get(f"{CHANNELS}/{general['id']}/messages", headers=auth_headers(other)).json()

    assert forbidden.status_code == 403
    assert edited.json()["body"] == "version finale"
    assert edited.json()["edited_at"] is not None
    assert deleted.json()["is_deleted"] is True
    assert listed[0]["body"] == ""
    assert listed[0]["is_deleted"] is True


def test_admin_can_moderate_public_messages(client, make_user, auth_headers, general):
    author, admin = make_user(), make_user(AccessLevel.ADMIN)
    message = post(client, auth_headers(author), general).json()

    response = client.delete(f"/api/v1/messages/{message['id']}", headers=auth_headers(admin))

    assert response.status_code == 200


def test_reactions_are_counted_per_emoji(client, make_user, auth_headers, general):
    alice, bob = make_user(), make_user()
    message = post(client, auth_headers(alice), general).json()
    url = f"/api/v1/messages/{message['id']}/reactions"

    client.put(f"{url}/👍", headers=auth_headers(alice))
    client.put(f"{url}/👍", headers=auth_headers(alice))
    reacted = client.put(f"{url}/👍", headers=auth_headers(bob)).json()
    removed = client.delete(f"{url}/👍", headers=auth_headers(bob)).json()

    assert reacted["reactions"] == [{"emoji": "👍", "count": 2, "reacted_by_me": True}]
    assert removed["reactions"] == [{"emoji": "👍", "count": 1, "reacted_by_me": False}]


def test_archived_channel_is_read_only(client, make_user, auth_headers):
    manager = make_user(AccessLevel.MANAGER)
    headers = auth_headers(manager)
    channel = client.post(
        CHANNELS, headers=headers, json={"kind": "public", "name": "vieux"}
    ).json()

    client.patch(f"{CHANNELS}/{channel['id']}", headers=headers, json={"is_archived": True})

    assert post(client, headers, channel).status_code == 403
    assert client.get(CHANNELS, headers=headers).json() == []


# ---------- Notifications ----------


def test_task_assignment_and_meeting_invite_notify(client, team):
    client.post(
        f"/api/v1/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": "Maquettes", "assignee_id": str(team["contributor"].id)},
    )
    client.post(
        "/api/v1/meetings",
        headers=team["h"]["lead"],
        json={
            "title": "Kick-off",
            "scheduled_at": "2026-10-01T09:00:00+00:00",
            "participant_ids": [str(team["contributor"].id)],
        },
    )

    notifications = client.get("/api/v1/notifications", headers=team["h"]["contributor"]).json()
    lead_notifications = client.get("/api/v1/notifications", headers=team["h"]["lead"]).json()

    assert {n["kind"] for n in notifications} == {"task_assigned", "meeting_invite"}
    assert lead_notifications == []


def test_mark_notifications_read(client, team):
    for title in ("A", "B"):
        client.post(
            f"/api/v1/projects/{team['project']['id']}/tasks",
            headers=team["h"]["lead"],
            json={"title": title, "assignee_id": str(team["contributor"].id)},
        )
    headers = team["h"]["contributor"]
    first, _ = client.get("/api/v1/notifications", headers=headers).json()

    client.post(f"/api/v1/notifications/{first['id']}/read", headers=headers)
    unread = client.get("/api/v1/notifications", headers=headers, params={"unread_only": True})
    other_user = client.post(
        f"/api/v1/notifications/{first['id']}/read", headers=team["h"]["viewer"]
    )
    dashboard = client.get("/api/v1/dashboard", headers=headers).json()
    client.post("/api/v1/notifications/read-all", headers=headers)
    after = client.get("/api/v1/notifications", headers=headers, params={"unread_only": True})

    assert len(unread.json()) == 1
    assert other_user.status_code == 404
    assert dashboard["me"]["unread_notifications"] == 1
    assert after.json() == []


# ---------- Temps réel ----------


def ws_login(ws, token):
    ws.send_json({"type": "auth", "token": token})
    assert ws.receive_json() == {"type": "ready"}


def test_websocket_pushes_messages_and_notifications(client, make_user, login, general):
    alice, bob = make_user(), make_user()
    alice_token = login(alice)["access_token"]
    bob_headers = {"Authorization": f"Bearer {login(bob)['access_token']}"}

    with client.websocket_connect("/api/v1/ws") as ws:
        ws_login(ws, alice_token)
        post(client, bob_headers, general, "Coucou @alice", mentioned_user_ids=[str(alice.id)])
        events = [ws.receive_json(), ws.receive_json()]

    by_type = {e["type"]: e for e in events}
    assert by_type["message.created"]["message"]["body"] == "Coucou @alice"
    assert by_type["notification.created"]["notification"]["kind"] == "mention"


def test_websocket_does_not_leak_private_messages(client, make_user, login, auth_headers):
    owner, friend, spy = make_user(), make_user(), make_user()
    group = client.post(
        CHANNELS,
        headers=auth_headers(owner),
        json={"kind": "private", "name": "G", "member_ids": [str(friend.id)]},
    ).json()
    public = client.post(
        CHANNELS,
        headers=auth_headers(make_user(AccessLevel.MANAGER)),
        json={"kind": "public", "name": "p"},
    ).json()

    with client.websocket_connect("/api/v1/ws") as ws:
        ws_login(ws, login(spy)["access_token"])
        post(client, auth_headers(owner), group, "secret")
        post(client, auth_headers(owner), public, "public")
        event = ws.receive_json()

    # Le premier événement reçu est le message public : le privé n'a pas été diffusé.
    assert event["message"]["body"] == "public"


def test_websocket_rejects_invalid_token(client):
    with client.websocket_connect("/api/v1/ws") as ws:
        ws.send_json({"type": "auth", "token": "garbage"})
        message = ws.receive()

    assert message["type"] == "websocket.close"
    assert message["code"] == 4001
