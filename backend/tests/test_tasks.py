import pytest

PROJECTS = "/api/v1/projects"
TASKS = "/api/v1/tasks"


def tasks_url(team) -> str:
    return f"{PROJECTS}/{team['project']['id']}/tasks"


def create_task(client, team, role="contributor", **fields):
    response = client.post(tasks_url(team), headers=team["h"][role], json={"title": "T", **fields})
    assert response.status_code == 201, response.text
    return response.json()


# ---------- Phases ----------


def test_lead_creates_ordered_phases(client, team):
    url = f"{PROJECTS}/{team['project']['id']}/phases"
    for name in ("Analyse", "Backend", "Mobile"):
        assert client.post(url, headers=team["h"]["lead"], json={"name": name}).status_code == 201

    phases = client.get(url, headers=team["h"]["viewer"]).json()

    assert [(p["name"], p["position"]) for p in phases] == [
        ("Analyse", 0),
        ("Backend", 1),
        ("Mobile", 2),
    ]


def test_contributor_cannot_manage_phases(client, team):
    url = f"{PROJECTS}/{team['project']['id']}/phases"

    response = client.post(url, headers=team["h"]["contributor"], json={"name": "X"})

    assert response.status_code == 403


def test_deleting_a_phase_keeps_its_tasks(client, team):
    url = f"{PROJECTS}/{team['project']['id']}/phases"
    phase = client.post(url, headers=team["h"]["lead"], json={"name": "Tests"}).json()
    task = create_task(client, team, phase_id=phase["id"])

    client.delete(f"{url}/{phase['id']}", headers=team["h"]["lead"])
    reloaded = client.get(f"{TASKS}/{task['id']}", headers=team["h"]["lead"]).json()

    assert reloaded["phase_id"] is None


def test_task_rejects_phase_of_another_project(client, team, make_user, auth_headers):
    other = client.post(PROJECTS, headers=team["h"]["lead"], json={"name": "Autre"}).json()
    phase = client.post(
        f"{PROJECTS}/{other['id']}/phases", headers=team["h"]["lead"], json={"name": "P"}
    ).json()

    response = client.post(
        tasks_url(team), headers=team["h"]["lead"], json={"title": "T", "phase_id": phase["id"]}
    )

    assert response.status_code == 400


# ---------- Tâches ----------


def test_contributor_creates_task_with_checklist(client, team):
    task = create_task(
        client,
        team,
        title="Maquettes",
        priority="high",
        assignee_id=str(team["contributor"].id),
        checklist=["Accueil", " ", "Profil"],
    )

    assert task["status"] == "todo"
    assert task["assignee"]["id"] == str(team["contributor"].id)
    assert [i["label"] for i in task["checklist"]] == ["Accueil", "Profil"]


def test_viewer_cannot_create_or_update_tasks(client, team):
    task = create_task(client, team)

    created = client.post(tasks_url(team), headers=team["h"]["viewer"], json={"title": "X"})
    updated = client.patch(
        f"{TASKS}/{task['id']}", headers=team["h"]["viewer"], json={"status": "done"}
    )

    assert created.status_code == 403
    assert updated.status_code == 403


def test_outsider_gets_404_on_task(client, team):
    task = create_task(client, team)

    assert client.get(f"{TASKS}/{task['id']}", headers=team["h"]["outsider"]).status_code == 404


def test_task_cannot_be_assigned_outside_the_project(client, team):
    response = client.post(
        tasks_url(team),
        headers=team["h"]["lead"],
        json={"title": "T", "assignee_id": str(team["outsider"].id)},
    )

    assert response.status_code == 400


def test_kanban_status_changes_set_completion_time(client, team):
    task = create_task(client, team)
    url = f"{TASKS}/{task['id']}"
    headers = team["h"]["contributor"]

    done = client.patch(url, headers=headers, json={"status": "done"}).json()
    reopened = client.patch(url, headers=headers, json={"status": "review"}).json()

    assert done["completed_at"] is not None
    assert reopened["completed_at"] is None


def test_list_tasks_filters_by_status_and_assignee(client, team):
    mine = create_task(client, team, assignee_id=str(team["contributor"].id))
    create_task(client, team, status="in_progress")
    headers = team["h"]["viewer"]

    by_status = client.get(f"{tasks_url(team)}?status=in_progress", headers=headers).json()
    by_assignee = client.get(
        f"{tasks_url(team)}?assignee_id={team['contributor'].id}", headers=headers
    ).json()

    assert len(by_status) == 1
    assert [t["id"] for t in by_assignee] == [mine["id"]]


def test_only_lead_deletes_tasks(client, team):
    task = create_task(client, team)
    url = f"{TASKS}/{task['id']}"

    assert client.delete(url, headers=team["h"]["contributor"]).status_code == 403
    assert client.delete(url, headers=team["h"]["lead"]).status_code == 204


def test_task_update_rejects_null_title(client, team):
    task = create_task(client, team)

    response = client.patch(
        f"{TASKS}/{task['id']}", headers=team["h"]["lead"], json={"title": None}
    )

    assert response.status_code == 422


# ---------- Dépendances ----------


def test_task_cannot_be_done_before_its_dependencies(client, team):
    backend = create_task(client, team, title="Backend")
    mobile = create_task(client, team, title="Mobile", depends_on_ids=[backend["id"]])
    headers = team["h"]["contributor"]

    blocked = client.patch(f"{TASKS}/{mobile['id']}", headers=headers, json={"status": "done"})
    client.patch(f"{TASKS}/{backend['id']}", headers=headers, json={"status": "done"})
    allowed = client.patch(f"{TASKS}/{mobile['id']}", headers=headers, json={"status": "done"})

    assert blocked.status_code == 409
    assert "Backend" in blocked.json()["detail"]
    assert allowed.status_code == 200


def test_dependents_are_listed(client, team):
    backend = create_task(client, team, title="Backend")
    create_task(client, team, title="Mobile", depends_on_ids=[backend["id"]])

    detail = client.get(f"{TASKS}/{backend['id']}", headers=team["h"]["viewer"]).json()

    assert [d["title"] for d in detail["dependents"]] == ["Mobile"]


def test_dependency_cycles_are_rejected(client, team):
    a = create_task(client, team, title="A")
    b = create_task(client, team, title="B", depends_on_ids=[a["id"]])
    c = create_task(client, team, title="C", depends_on_ids=[b["id"]])

    response = client.put(
        f"{TASKS}/{a['id']}/dependencies",
        headers=team["h"]["contributor"],
        json={"depends_on_ids": [c["id"]]},
    )

    assert response.status_code == 409


def test_self_dependency_is_rejected(client, team):
    a = create_task(client, team)

    response = client.put(
        f"{TASKS}/{a['id']}/dependencies",
        headers=team["h"]["contributor"],
        json={"depends_on_ids": [a["id"]]},
    )

    assert response.status_code == 400


def test_dependencies_must_be_in_the_same_project(client, team):
    other = client.post(PROJECTS, headers=team["h"]["lead"], json={"name": "Autre"}).json()
    foreign = client.post(
        f"{PROJECTS}/{other['id']}/tasks", headers=team["h"]["lead"], json={"title": "X"}
    ).json()

    response = client.post(
        tasks_url(team),
        headers=team["h"]["lead"],
        json={"title": "T", "depends_on_ids": [foreign["id"]]},
    )

    assert response.status_code == 400


# ---------- Checklist, commentaires, historique ----------


def test_checklist_lifecycle(client, team):
    task = create_task(client, team)
    url = f"{TASKS}/{task['id']}/checklist"
    headers = team["h"]["contributor"]

    item = client.post(url, headers=headers, json={"label": "Relire"}).json()
    checked = client.patch(f"{url}/{item['id']}", headers=headers, json={"is_done": True}).json()
    deleted = client.delete(f"{url}/{item['id']}", headers=headers)
    missing = client.delete(f"{url}/{item['id']}", headers=headers)

    assert checked["is_done"] is True
    assert deleted.status_code == 204
    assert missing.status_code == 404


def test_comments_are_listed_in_order(client, team):
    task = create_task(client, team)
    url = f"{TASKS}/{task['id']}/comments"

    client.post(url, headers=team["h"]["contributor"], json={"body": "Premier"})
    client.post(url, headers=team["h"]["lead"], json={"body": "Second"})
    comments = client.get(url, headers=team["h"]["viewer"]).json()

    assert [c["body"] for c in comments] == ["Premier", "Second"]
    assert comments[0]["author"]["id"] == str(team["contributor"].id)


def test_viewer_cannot_comment(client, team):
    task = create_task(client, team)

    response = client.post(
        f"{TASKS}/{task['id']}/comments", headers=team["h"]["viewer"], json={"body": "x"}
    )

    assert response.status_code == 403


def test_history_records_who_changed_what(client, team):
    task = create_task(client, team, title="Maquettes")
    client.patch(
        f"{TASKS}/{task['id']}", headers=team["h"]["contributor"], json={"status": "in_progress"}
    )

    history = client.get(f"{TASKS}/{task['id']}/history", headers=team["h"]["viewer"]).json()

    assert [h["action"] for h in history] == ["status_changed", "created"]
    assert history[0]["actor"]["id"] == str(team["contributor"].id)
    assert history[0]["changes"] == {"status": {"from": "todo", "to": "in_progress"}}


def test_project_activity_feed_includes_project_and_task_events(client, team):
    create_task(client, team)

    feed = client.get(
        f"{PROJECTS}/{team['project']['id']}/activity", headers=team["h"]["viewer"]
    ).json()
    actions = {(e["entity_type"], e["action"]) for e in feed}

    assert {("project", "created"), ("project", "member_set"), ("task", "created")} <= actions


@pytest.mark.parametrize("role", ["outsider"])
def test_outsider_cannot_read_project_activity(client, team, role):
    response = client.get(f"{PROJECTS}/{team['project']['id']}/activity", headers=team["h"][role])

    assert response.status_code == 404
