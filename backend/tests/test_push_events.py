"""Chaque action de l'app déclenche le bon push, vers les bonnes personnes."""

import io

import pytest

from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind
from tests.test_meetings import add_decision, create_meeting

API = "/api/v1"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


@pytest.fixture
def general(db) -> dict:
    channel = Channel(kind=ChannelKind.PUBLIC, name="général")
    db.add(channel)
    db.commit()
    return {"id": str(channel.id)}


def _task(client, team, **fields) -> dict:
    url = f"{API}/projects/{team['project']['id']}/tasks"
    response = client.post(url, headers=team["h"]["lead"], json={"title": "API", **fields})
    assert response.status_code == 201, response.text
    return response.json()


# ---------- Messages ----------


def test_message_is_pushed_to_everyone_else_in_the_channel(
    client, make_user, auth_headers, general, pushes
):
    alice, bob, carol = make_user(), make_user(), make_user()

    client.post(
        f"{API}/channels/{general['id']}/messages",
        headers=auth_headers(alice),
        json={"body": "Réunion   à 10h"},
    )

    assert pushes.to(alice) == []
    for member in (bob, carol):
        (push,) = pushes.to(member)
        assert push.type == "message"
        assert push.title == f"{alice.full_name} · #général"
        assert push.body == "Réunion à 10h"
        assert (push.entity_type, str(push.entity_id)) == ("channel", general["id"])


def test_mentioned_member_gets_the_mention_not_a_duplicate(
    client, make_user, auth_headers, general, pushes
):
    alice, bob = make_user(), make_user()

    client.post(
        f"{API}/channels/{general['id']}/messages",
        headers=auth_headers(alice),
        json={"body": "@Bob tu relis ?", "mentioned_user_ids": [str(bob.id)]},
    )

    assert pushes.types_to(bob) == ["mention"]


def test_direct_message_push_is_titled_with_the_author(client, make_user, auth_headers, pushes):
    alice, bob, outsider = make_user(), make_user(), make_user()
    channel = client.post(
        f"{API}/channels/direct", headers=auth_headers(alice), json={"user_id": str(bob.id)}
    ).json()

    client.post(
        f"{API}/channels/{channel['id']}/messages",
        headers=auth_headers(alice),
        json={"body": "Salut"},
    )

    assert [p.title for p in pushes.to(bob)] == [alice.full_name]
    assert pushes.to(outsider) == []


def test_attachment_push_describes_the_file(client, make_user, auth_headers, general, pushes):
    alice, bob = make_user(), make_user()

    client.post(
        f"{API}/channels/{general['id']}/attachments",
        headers=auth_headers(alice),
        files={"file": ("plage.png", PNG)},
    )

    assert [p.body for p in pushes.to(bob)] == ["[photo : plage.png]"]


def test_project_channel_message_stays_within_the_project(client, team, pushes):
    channel = client.get(
        f"{API}/projects/{team['project']['id']}/channel", headers=team["h"]["lead"]
    )
    assert channel.status_code == 200, channel.text

    client.post(
        f"{API}/channels/{channel.json()['id']}/messages",
        headers=team["h"]["lead"],
        json={"body": "Sprint lancé"},
    )

    assert pushes.types_to(team["contributor"]) == ["message"]
    assert pushes.to(team["outsider"]) == []


# ---------- Projets ----------


def test_project_creation_and_new_members_are_notified(client, make_user, auth_headers, pushes):
    manager, lead, newcomer = make_user(AccessLevel.MANAGER), make_user(), make_user()
    headers = auth_headers(manager)

    project = client.post(
        f"{API}/projects", headers=headers, json={"name": "Astra Pay", "lead_id": str(lead.id)}
    ).json()
    members_url = f"{API}/projects/{project['id']}/members/{newcomer.id}"
    lead_headers = auth_headers(lead)
    client.put(members_url, headers=lead_headers, json={"role": "contributor"})
    # Simple changement de rôle : pas de nouvelle notification.
    client.put(members_url, headers=lead_headers, json={"role": "viewer"})

    assert pushes.to(manager) == []
    for member in (lead, newcomer):
        (push,) = pushes.to(member)
        assert push.type == "project_added"
        assert "Astra Pay" in push.title
        assert str(push.entity_id) == project["id"]


def test_project_status_change_reaches_all_members(client, team, pushes):
    client.patch(
        f"{API}/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"status": "active"},
    )
    client.patch(  # autre champ : pas de push
        f"{API}/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"description": "Nouvelle description"},
    )

    assert pushes.to(team["lead"]) == []
    for role in ("contributor", "viewer"):
        (push,) = pushes.to(team[role])
        assert push.type == "project_status"
        assert push.title.endswith(": Actif")
    assert pushes.to(team["outsider"]) == []


# ---------- Tâches ----------


def test_task_assignment_is_pushed(client, team, pushes):
    task = _task(client, team, assignee_id=str(team["contributor"].id))

    (push,) = pushes.to(team["contributor"])
    assert (push.type, push.body, str(push.entity_id)) == ("task_assigned", "API", task["id"])


def test_status_change_notifies_assignee_and_creator(client, team, pushes):
    task = _task(client, team, assignee_id=str(team["contributor"].id))

    client.patch(
        f"{API}/tasks/{task['id']}", headers=team["h"]["contributor"], json={"status": "review"}
    )

    assert pushes.types_to(team["contributor"]) == ["task_assigned"]
    (push,) = pushes.to(team["lead"])
    assert push.type == "task_status"
    assert "« En revue »" in push.title


def test_reassignment_with_status_change_is_a_single_push(client, team, pushes):
    task = _task(client, team)

    client.patch(
        f"{API}/tasks/{task['id']}",
        headers=team["h"]["lead"],
        json={"assignee_id": str(team["contributor"].id), "status": "in_progress"},
    )

    assert pushes.types_to(team["contributor"]) == ["task_assigned"]


def test_comment_notifies_followers_who_still_have_access(client, team, pushes):
    task = _task(client, team, assignee_id=str(team["contributor"].id))
    url = f"{API}/tasks/{task['id']}/comments"
    client.post(url, headers=team["h"]["contributor"], json={"body": "Je m'en occupe"})

    client.post(url, headers=team["h"]["lead"], json={"body": "Merci"})
    client.delete(
        f"{API}/projects/{team['project']['id']}/members/{team['contributor'].id}",
        headers=team["h"]["lead"],
    )
    client.post(url, headers=team["h"]["lead"], json={"body": "Je reprends"})

    assert [p.body for p in pushes.to(team["lead"]) if p.type == "task_comment"] == [
        "Je m'en occupe"
    ]
    # Retiré du projet : plus aucune notification sur ses anciennes tâches.
    assert [p.body for p in pushes.to(team["contributor"]) if p.type == "task_comment"] == ["Merci"]


# ---------- Réunions ----------


def test_meeting_invite_update_and_cancellation(client, make_user, auth_headers, pushes):
    organizer, guest, late_guest = make_user(), make_user(), make_user()
    headers = auth_headers(organizer)
    meeting = create_meeting(client, headers, participant_ids=[str(guest.id)])
    url = f"{API}/meetings/{meeting['id']}"

    client.patch(
        url,
        headers=headers,
        json={
            "location": "Salle Orion",
            "participant_ids": [str(guest.id), str(late_guest.id)],
        },
    )
    client.patch(url, headers=headers, json={"agenda": "1. Budget"})  # pas de push
    client.patch(url, headers=headers, json={"status": "cancelled"})

    assert pushes.types_to(guest) == ["meeting_invite", "meeting_updated", "meeting_cancelled"]
    assert pushes.types_to(late_guest) == ["meeting_invite", "meeting_cancelled"]
    assert pushes.to(organizer) == []
    assert "Salle Orion" in pushes.to(guest)[1].body


def test_minutes_publication_is_pushed(client, make_user, auth_headers, pushes):
    organizer, guest = make_user(), make_user()
    headers = auth_headers(organizer)
    meeting = create_meeting(client, headers, participant_ids=[str(guest.id)])

    client.patch(f"{API}/meetings/{meeting['id']}", headers=headers, json={"minutes": "RAS"})

    assert pushes.to(guest)[-1].title == "Compte rendu disponible : Point hebdo"


def test_deleting_a_planned_meeting_tells_participants(client, make_user, auth_headers, pushes):
    organizer, guest = make_user(), make_user()
    headers = auth_headers(organizer)
    meeting = create_meeting(client, headers, participant_ids=[str(guest.id)])

    client.delete(f"{API}/meetings/{meeting['id']}", headers=headers)

    push = pushes.to(guest)[-1]
    assert (push.type, push.entity_type) == ("meeting_cancelled", "deleted")


# ---------- Décisions ----------


def test_decision_goes_to_reviewers_then_back_to_its_author(client, team, pushes):
    decision = client.post(
        f"{API}/projects/{team['project']['id']}/decisions",
        headers=team["h"]["contributor"],
        json={"title": "Passer à Flutter 4"},
    ).json()

    (proposed,) = pushes.to(team["lead"])
    assert (proposed.type, proposed.body) == ("decision_proposed", "Passer à Flutter 4")
    assert (proposed.entity_type, str(proposed.entity_id)) == ("project", team["project"]["id"])

    client.post(
        f"{API}/decisions/{decision['id']}/review",
        headers=team["h"]["lead"],
        json={"status": "rejected"},
    )

    (reviewed,) = pushes.to(team["contributor"])
    assert reviewed.type == "decision_reviewed"
    assert "rejeté" in reviewed.title


def test_meeting_decision_goes_to_the_organizer(client, make_user, auth_headers, pushes):
    organizer = make_user()
    meeting = create_meeting(client, auth_headers(organizer))

    add_decision(client, auth_headers(organizer), meeting)

    # L'organisateur est l'auteur : il ne se notifie pas lui-même.
    assert pushes.to(organizer) == []


# ---------- Documents et groupes ----------


def test_project_document_upload_notifies_members(client, team, pushes):
    response = client.post(
        f"{API}/projects/{team['project']['id']}/documents",
        headers=team["h"]["contributor"],
        data={"title": "Cahier des charges", "kind": "specification"},
        files={"file": ("cdc.md", io.BytesIO(b"# CDC"), "text/markdown")},
    )
    assert response.status_code == 201, response.text

    assert pushes.to(team["contributor"]) == []
    for role in ("lead", "viewer"):
        (push,) = pushes.to(team[role])
        assert push.type == "document_added"
        assert push.body.startswith("Cahier des charges")
    assert pushes.to(team["outsider"]) == []


def test_private_group_members_are_notified_when_added(client, make_user, auth_headers, pushes):
    owner, friend, newcomer = make_user(), make_user(), make_user()
    headers = auth_headers(owner)
    group = client.post(
        f"{API}/channels",
        headers=headers,
        json={"kind": "private", "name": "mobile", "member_ids": [str(friend.id)]},
    ).json()

    client.put(f"{API}/channels/{group['id']}/members/{newcomer.id}", headers=headers)
    client.put(f"{API}/channels/{group['id']}/members/{newcomer.id}", headers=headers)

    assert pushes.types_to(friend) == ["channel_added"]
    assert pushes.types_to(newcomer) == ["channel_added"]
    assert pushes.to(owner) == []
