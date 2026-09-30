from datetime import date

from app.models.enums import AccessLevel

MEETINGS = "/api/v1/meetings"
DECISIONS = "/api/v1/decisions"
WHEN = "2026-10-01T09:00:00+00:00"


def create_meeting(client, headers, **fields):
    response = client.post(
        MEETINGS, headers=headers, json={"title": "Point hebdo", "scheduled_at": WHEN, **fields}
    )
    assert response.status_code == 201, response.text
    return response.json()


def project_meeting(client, team, **fields):
    return create_meeting(client, team["h"]["lead"], project_id=team["project"]["id"], **fields)


def add_decision(client, headers, meeting, title="Créer MarketCM V2"):
    response = client.post(
        f"{MEETINGS}/{meeting['id']}/decisions", headers=headers, json={"title": title}
    )
    assert response.status_code == 201, response.text
    return response.json()


# ---------- Réunions ----------


def test_organizer_is_always_a_participant(client, make_user, auth_headers):
    organizer, guest = make_user(), make_user()

    meeting = create_meeting(
        client, auth_headers(organizer), participant_ids=[str(guest.id)], agenda="1. Budget"
    )

    assert {p["id"] for p in meeting["participants"]} == {str(organizer.id), str(guest.id)}
    assert meeting["can_edit"] is True


def test_general_meeting_is_private_to_its_participants(client, make_user, auth_headers):
    organizer, guest, stranger = make_user(), make_user(), make_user()
    meeting = create_meeting(client, auth_headers(organizer), participant_ids=[str(guest.id)])
    url = f"{MEETINGS}/{meeting['id']}"

    guest_view = client.get(url, headers=auth_headers(guest))
    stranger_view = client.get(url, headers=auth_headers(stranger))
    stranger_list = client.get(MEETINGS, headers=auth_headers(stranger)).json()

    assert guest_view.status_code == 200
    assert guest_view.json()["can_edit"] is False
    assert stranger_view.status_code == 404
    assert stranger_list == []


def test_project_meeting_is_visible_to_project_members(client, team):
    meeting = project_meeting(client, team)
    url = f"{MEETINGS}/{meeting['id']}"

    assert client.get(url, headers=team["h"]["viewer"]).status_code == 200
    assert client.get(url, headers=team["h"]["outsider"]).status_code == 404


def test_viewer_cannot_schedule_project_meeting(client, team):
    response = client.post(
        MEETINGS,
        headers=team["h"]["viewer"],
        json={"title": "X", "scheduled_at": WHEN, "project_id": team["project"]["id"]},
    )

    assert response.status_code == 403


def test_outsider_cannot_attach_meeting_to_hidden_project(client, team):
    response = client.post(
        MEETINGS,
        headers=team["h"]["outsider"],
        json={"title": "X", "scheduled_at": WHEN, "project_id": team["project"]["id"]},
    )

    assert response.status_code == 404


def test_only_organizer_or_lead_edits_meeting(client, team):
    meeting = create_meeting(
        client,
        team["h"]["contributor"],
        project_id=team["project"]["id"],
        participant_ids=[str(team["viewer"].id)],
    )
    url = f"{MEETINGS}/{meeting['id']}"

    by_viewer = client.patch(url, headers=team["h"]["viewer"], json={"minutes": "x"})
    by_lead = client.patch(
        url, headers=team["h"]["lead"], json={"minutes": "Compte rendu", "status": "done"}
    )

    assert by_viewer.status_code == 403
    assert by_lead.status_code == 200
    assert by_lead.json()["minutes"] == "Compte rendu"
    assert by_lead.json()["status"] == "done"


def test_meeting_requires_timezone_aware_datetime(client, make_user, auth_headers):
    response = client.post(
        MEETINGS,
        headers=auth_headers(make_user()),
        json={"title": "X", "scheduled_at": "2026-10-01T09:00:00"},
    )

    assert response.status_code == 422


def test_meetings_are_filtered_by_period(client, make_user, auth_headers):
    headers = auth_headers(make_user())
    create_meeting(client, headers, title="Octobre")
    create_meeting(client, headers, title="Novembre", scheduled_at="2026-11-05T09:00:00+00:00")

    listed = client.get(
        MEETINGS,
        headers=headers,
        params={"start": "2026-10-01T00:00:00+00:00", "end": "2026-11-01T00:00:00+00:00"},
    ).json()

    assert [m["title"] for m in listed] == ["Octobre"]


def test_replacing_participants_keeps_the_organizer(client, make_user, auth_headers):
    organizer, a, b = make_user(), make_user(), make_user()
    headers = auth_headers(organizer)
    meeting = create_meeting(client, headers, participant_ids=[str(a.id)])

    updated = client.patch(
        f"{MEETINGS}/{meeting['id']}", headers=headers, json={"participant_ids": [str(b.id)]}
    ).json()

    assert {p["id"] for p in updated["participants"]} == {str(organizer.id), str(b.id)}


def test_meeting_generates_project_tasks(client, team):
    meeting = project_meeting(client, team)

    response = client.post(
        f"{MEETINGS}/{meeting['id']}/tasks",
        headers=team["h"]["lead"],
        json=[
            {"title": "Rédiger la spec", "assignee_id": str(team["contributor"].id)},
            {"title": "Chiffrer"},
        ],
    )
    task = client.get(
        f"/api/v1/tasks/{response.json()[0]['id']}", headers=team["h"]["viewer"]
    ).json()

    assert response.status_code == 201
    assert task["meeting_id"] == meeting["id"]


def test_meeting_tasks_are_all_or_nothing(client, team):
    meeting = project_meeting(client, team)

    response = client.post(
        f"{MEETINGS}/{meeting['id']}/tasks",
        headers=team["h"]["lead"],
        json=[{"title": "OK"}, {"title": "KO", "assignee_id": str(team["outsider"].id)}],
    )
    tasks = client.get(
        f"/api/v1/projects/{team['project']['id']}/tasks", headers=team["h"]["lead"]
    ).json()

    assert response.status_code == 400
    assert tasks == []


def test_general_meeting_cannot_generate_tasks(client, make_user, auth_headers):
    headers = auth_headers(make_user())
    meeting = create_meeting(client, headers)

    response = client.post(
        f"{MEETINGS}/{meeting['id']}/tasks", headers=headers, json=[{"title": "X"}]
    )

    assert response.status_code == 400


def test_my_work_and_dashboard_include_my_meetings(client, make_user, auth_headers):
    member = make_user()
    headers = auth_headers(member)
    create_meeting(client, headers, title="Aujourd'hui")
    create_meeting(client, headers, title="Dans 3 jours", scheduled_at="2026-10-04T09:00:00+00:00")

    work = client.get("/api/v1/me/work", headers=headers, params={"today": "2026-10-01"}).json()
    dashboard = client.get(
        "/api/v1/dashboard", headers=headers, params={"today": str(date(2026, 10, 1))}
    ).json()

    assert [m["title"] for m in work["meetings"]] == ["Aujourd'hui", "Dans 3 jours"]
    assert dashboard["me"]["upcoming_meetings"] == 1


# ---------- Décisions ----------


def test_decision_lifecycle_to_project(client, make_user, auth_headers):
    manager, contributor = make_user(AccessLevel.MANAGER), make_user()
    headers = auth_headers(manager)
    meeting = create_meeting(client, headers, participant_ids=[str(contributor.id)])
    decision = add_decision(client, headers, meeting)
    assert decision["status"] == "proposed"

    early = client.post(
        f"{DECISIONS}/{decision['id']}/project", headers=headers, json={"name": "MarketCM V2"}
    )
    validated = client.post(
        f"{DECISIONS}/{decision['id']}/review", headers=headers, json={"status": "validated"}
    )
    project = client.post(
        f"{DECISIONS}/{decision['id']}/project",
        headers=headers,
        json={
            "name": "MarketCM V2",
            "member_ids": [str(contributor.id)],
            "phases": [
                {"name": "Architecture", "tasks": [{"title": "Schéma de données"}]},
                {"name": "Backend", "tasks": [{"title": "API", "priority": "high"}]},
                {"name": "Mobile"},
                {"name": "Tests"},
            ],
        },
    )
    again = client.post(
        f"{DECISIONS}/{decision['id']}/project", headers=headers, json={"name": "Doublon"}
    )

    assert early.status_code == 409
    assert validated.json()["status"] == "validated"
    assert project.status_code == 201, project.text
    body = project.json()
    assert body["status"] == "planning"
    assert {m["user"]["id"] for m in body["members"]} == {str(manager.id), str(contributor.id)}
    phases = client.get(f"/api/v1/projects/{body['id']}/phases", headers=headers).json()
    assert [p["name"] for p in phases] == ["Architecture", "Backend", "Mobile", "Tests"]
    tasks = client.get(f"/api/v1/projects/{body['id']}/tasks", headers=headers).json()
    assert {t["title"] for t in tasks} == {"Schéma de données", "API"}
    reloaded = client.get(f"{DECISIONS}/{decision['id']}", headers=headers).json()
    assert reloaded["resulting_project_id"] == body["id"]
    assert again.status_code == 409


def test_plain_member_cannot_turn_decision_into_project(client, make_user, auth_headers):
    member = make_user()
    headers = auth_headers(member)
    meeting = create_meeting(client, headers)
    decision = add_decision(client, headers, meeting)
    client.post(
        f"{DECISIONS}/{decision['id']}/review", headers=headers, json={"status": "validated"}
    )

    response = client.post(
        f"{DECISIONS}/{decision['id']}/project", headers=headers, json={"name": "P"}
    )

    assert response.status_code == 403


def test_participant_cannot_add_or_validate_decisions(client, make_user, auth_headers):
    organizer, guest = make_user(), make_user()
    meeting = create_meeting(client, auth_headers(organizer), participant_ids=[str(guest.id)])
    decision = add_decision(client, auth_headers(organizer), meeting)

    added = client.post(
        f"{MEETINGS}/{meeting['id']}/decisions", headers=auth_headers(guest), json={"title": "X"}
    )
    reviewed = client.post(
        f"{DECISIONS}/{decision['id']}/review",
        headers=auth_headers(guest),
        json={"status": "validated"},
    )

    assert added.status_code == 403
    assert reviewed.status_code == 403


def test_decision_cannot_be_reset_to_proposed(client, make_user, auth_headers):
    headers = auth_headers(make_user())
    decision = add_decision(client, headers, create_meeting(client, headers))

    response = client.post(
        f"{DECISIONS}/{decision['id']}/review", headers=headers, json={"status": "proposed"}
    )

    assert response.status_code == 400


def test_project_decision_visibility_and_review(client, team):
    url = f"/api/v1/projects/{team['project']['id']}/decisions"
    decision = client.post(url, headers=team["h"]["contributor"], json={"title": "Choisir FastAPI"})
    decision_id = decision.json()["id"]

    by_contributor = client.post(
        f"{DECISIONS}/{decision_id}/review",
        headers=team["h"]["contributor"],
        json={"status": "validated"},
    )
    by_lead = client.post(
        f"{DECISIONS}/{decision_id}/review", headers=team["h"]["lead"], json={"status": "validated"}
    )
    outsider = client.get(f"{DECISIONS}/{decision_id}", headers=team["h"]["outsider"])
    listed = client.get(
        DECISIONS, headers=team["h"]["viewer"], params={"status": "validated"}
    ).json()

    assert decision.status_code == 201
    assert by_contributor.status_code == 403
    assert by_lead.status_code == 200
    assert outsider.status_code == 404
    assert [d["id"] for d in listed] == [decision_id]


def test_validated_project_decision_generates_tasks(client, team):
    url = f"/api/v1/projects/{team['project']['id']}/decisions"
    decision = client.post(url, headers=team["h"]["lead"], json={"title": "Refonte"}).json()
    tasks_url = f"{DECISIONS}/{decision['id']}/tasks"

    before = client.post(tasks_url, headers=team["h"]["lead"], json=[{"title": "X"}])
    client.post(
        f"{DECISIONS}/{decision['id']}/review",
        headers=team["h"]["lead"],
        json={"status": "validated"},
    )
    after = client.post(tasks_url, headers=team["h"]["lead"], json=[{"title": "Maquettes"}])

    assert before.status_code == 409
    assert after.status_code == 201
    task = client.get(f"/api/v1/tasks/{after.json()[0]['id']}", headers=team["h"]["lead"]).json()
    assert task["decision_id"] == decision["id"]


def test_meeting_detail_lists_its_decisions(client, make_user, auth_headers):
    headers = auth_headers(make_user())
    meeting = create_meeting(client, headers)
    add_decision(client, headers, meeting, "D1")

    detail = client.get(f"{MEETINGS}/{meeting['id']}", headers=headers).json()

    assert [d["title"] for d in detail["decisions"]] == ["D1"]
