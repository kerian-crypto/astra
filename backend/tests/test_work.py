from datetime import date, timedelta

TODAY = date(2026, 10, 1)


def create_task(client, team, **fields):
    response = client.post(
        f"/api/v1/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": "T", "assignee_id": str(team["contributor"].id), **fields},
    )
    assert response.status_code == 201, response.text
    return response.json()


def iso(days: int) -> str:
    return (TODAY + timedelta(days=days)).isoformat()


def test_my_work_sections(client, team):
    due_today = create_task(client, team, title="Aujourd'hui", due_date=iso(0))
    in_progress = create_task(client, team, title="En cours", status="in_progress")
    overdue = create_task(client, team, title="En retard", due_date=iso(-2))
    urgent = create_task(client, team, title="Urgent", priority="critical")
    soon = create_task(client, team, title="Bientôt", due_date=iso(3))
    create_task(client, team, title="Lointain", due_date=iso(30))
    create_task(client, team, title="Fini", due_date=iso(-1), status="done")

    work = client.get(f"/api/v1/me/work?today={TODAY}", headers=team["h"]["contributor"]).json()

    def ids(section):
        return {t["id"] for t in work[section]}

    assert ids("today") == {due_today["id"], in_progress["id"]}
    assert ids("overdue") == {overdue["id"]}
    assert ids("priority") == {urgent["id"]}
    assert ids("upcoming") == {soon["id"]}


def test_my_work_excludes_tasks_of_projects_i_left(client, team):
    create_task(client, team, due_date=iso(0))
    client.delete(
        f"/api/v1/projects/{team['project']['id']}/members/{team['contributor'].id}",
        headers=team["h"]["lead"],
    )

    work = client.get(f"/api/v1/me/work?today={TODAY}", headers=team["h"]["contributor"]).json()

    assert work["today"] == []


def test_dashboard_counts_only_visible_projects(client, team):
    client.patch(
        f"/api/v1/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"status": "active"},
    )
    create_task(client, team, due_date=iso(-1))
    create_task(client, team, due_date=iso(0))

    mine = client.get(f"/api/v1/dashboard?today={TODAY}", headers=team["h"]["contributor"]).json()
    outsider = client.get(f"/api/v1/dashboard?today={TODAY}", headers=team["h"]["outsider"]).json()

    assert mine["me"] == {
        "open_tasks": 2,
        "today_tasks": 1,
        "overdue_tasks": 1,
        "upcoming_meetings": 0,
        # une notification par tâche attribuée
        "unread_notifications": 2,
    }
    assert mine["astra"]["active_projects"] == 1
    assert mine["astra"]["overdue_tasks"] == 1
    attention = mine["astra"]["projects_needing_attention"]
    assert [(p["name"], p["overdue_tasks"]) for p in attention] == [("MarketCM V2", 1)]
    assert outsider["astra"] == {
        "active_projects": 0,
        "open_tasks": 0,
        "overdue_tasks": 0,
        "projects_needing_attention": [],
    }


def test_project_past_its_due_date_needs_attention(client, team):
    client.patch(
        f"/api/v1/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"status": "active", "due_date": iso(-5)},
    )

    dashboard = client.get(f"/api/v1/dashboard?today={TODAY}", headers=team["h"]["viewer"]).json()

    assert dashboard["astra"]["projects_needing_attention"][0]["reason"] == (
        "Échéance du projet dépassée"
    )
