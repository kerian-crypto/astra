from datetime import UTC, date, datetime, timedelta

from sqlalchemy import update

from app.models import Channel, Decision
from app.models.enums import AccessLevel, ChannelKind

TODAY = date(2026, 10, 1)


def create_task(client, team, **fields):
    response = client.post(
        f"/api/v1/projects/{team['project']['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": "T", **fields},
    )
    assert response.status_code == 201, response.text
    return response.json()


def search(client, headers, q, **params):
    return client.get("/api/v1/search", headers=headers, params={"q": q, **params})


# ---------- Recherche ----------


def test_search_finds_tasks_with_french_stemming(client, team):
    create_task(client, team, title="Déploiement de l'infrastructure", description="Serveurs")

    hits = search(client, team["h"]["viewer"], "déployer infrastructures").json()

    assert [(h["type"], h["title"]) for h in hits] == [("task", "Déploiement de l'infrastructure")]
    assert "«" in hits[0]["snippet"]


def test_search_never_returns_hidden_project_content(client, team):
    create_task(client, team, title="Budget confidentiel")

    assert search(client, team["h"]["outsider"], "budget confidentiel").json() == []


def test_search_skips_private_messages_of_other_people(client, make_user, auth_headers):
    owner, spy = make_user(), make_user()
    group = client.post(
        "/api/v1/channels",
        headers=auth_headers(owner),
        json={"kind": "private", "name": "Secret"},
    ).json()
    client.post(
        f"/api/v1/channels/{group['id']}/messages",
        headers=auth_headers(owner),
        json={"body": "Rachat prévu de la société Zephyr"},
    )

    mine = search(client, auth_headers(owner), "Zephyr").json()
    theirs = search(client, auth_headers(spy), "Zephyr").json()

    assert [h["type"] for h in mine] == ["message"]
    assert mine[0]["parent_id"] == group["id"]
    assert theirs == []


def test_search_can_filter_by_type(client, team, db):
    create_task(client, team, title="Refonte mobile")
    db.add(Channel(kind=ChannelKind.PUBLIC, name="général"))
    db.commit()

    hits = search(client, team["h"]["lead"], "refonte", types="project").json()

    assert hits == []


def test_search_rejects_too_short_query(client, team):
    assert search(client, team["h"]["lead"], "a").status_code == 422


# ---------- État de santé ----------


def test_health_detects_blocked_and_critical_tasks(client, team):
    backend = create_task(client, team, title="Backend")
    for title in ("Mobile", "Tests"):
        create_task(
            client,
            team,
            title=title,
            status="in_progress",
            depends_on_ids=[backend["id"]],
        )
    create_task(client, team, title="En retard", due_date=str(TODAY - timedelta(days=2)))

    health = client.get(
        "/api/v1/insights/health", headers=team["h"]["viewer"], params={"today": str(TODAY)}
    ).json()

    assert {t["title"] for t in health["blocked_tasks"]} == {"Mobile", "Tests"}
    assert [(c["task"]["title"], c["waiting_tasks"]) for c in health["critical_dependencies"]] == [
        ("Backend", 2)
    ]
    assert [t["title"] for t in health["overdue_tasks"]] == ["En retard"]


def test_health_flags_overloaded_members(client, team, db):
    team["contributor"].availability = 25  # capacité : 2 tâches
    db.commit()
    for index in range(3):
        create_task(client, team, title=f"T{index}", assignee_id=str(team["contributor"].id))

    health = client.get("/api/v1/insights/health", headers=team["h"]["lead"]).json()

    (overloaded,) = health["overloaded_members"]
    assert overloaded["member"]["id"] == str(team["contributor"].id)
    assert (overloaded["open_tasks"], overloaded["capacity"]) == (3, 2)


def test_health_lists_unexecuted_decisions(client, team, db):
    decision = client.post(
        f"/api/v1/projects/{team['project']['id']}/decisions",
        headers=team["h"]["lead"],
        json={"title": "Migrer vers PostgreSQL 17"},
    ).json()
    client.post(
        f"/api/v1/decisions/{decision['id']}/review",
        headers=team["h"]["lead"],
        json={"status": "validated"},
    )
    db.execute(update(Decision).values(validated_at=datetime(2026, 9, 1, tzinfo=UTC)))
    db.commit()

    health = client.get(
        "/api/v1/insights/health", headers=team["h"]["viewer"], params={"today": str(TODAY)}
    ).json()

    assert [d["title"] for d in health["unexecuted_decisions"]] == ["Migrer vers PostgreSQL 17"]


def test_health_reports_missing_information(client, team):
    client.patch(
        f"/api/v1/projects/{team['project']['id']}",
        headers=team["h"]["lead"],
        json={"status": "active"},
    )
    create_task(client, team, title="Sans responsable")

    health = client.get("/api/v1/insights/health", headers=team["h"]["lead"]).json()

    issues = {i["issue"] for i in health["missing_information"]}
    assert issues == {"Aucune échéance définie", "1 tâche(s) sans responsable"}


# ---------- Répartition du travail ----------


def test_assignment_suggestions_prefer_matching_skills_and_free_capacity(
    client, team, make_user, db
):
    team["contributor"].skills = ["Flutter", "FastAPI"]
    team["lead"].skills = ["Marketing"]
    db.commit()
    task = create_task(client, team, title="Écran de connexion Flutter")

    suggestions = client.get(
        f"/api/v1/tasks/{task['id']}/assignment-suggestions", headers=team["h"]["lead"]
    ).json()

    assert suggestions[0]["member"]["id"] == str(team["contributor"].id)
    assert "Compétences utiles : Flutter" in suggestions[0]["reasons"]
    # Les lecteurs ne sont pas proposés.
    assert str(team["viewer"].id) not in {s["member"]["id"] for s in suggestions}


def test_workload_of_project_members(client, team):
    create_task(client, team, assignee_id=str(team["contributor"].id))

    loads = client.get(
        f"/api/v1/projects/{team['project']['id']}/workload", headers=team["h"]["viewer"]
    ).json()
    outsider = client.get(
        f"/api/v1/projects/{team['project']['id']}/workload", headers=team["h"]["outsider"]
    )

    by_member = {load["member"]["id"]: load["open_tasks"] for load in loads}
    assert by_member[str(team["contributor"].id)] == 1
    assert len(loads) == 3
    assert outsider.status_code == 404


def test_admin_sees_every_project_in_health(client, team, make_user, auth_headers):
    create_task(client, team, title="Retard", due_date=str(TODAY - timedelta(days=1)))
    admin = make_user(AccessLevel.ADMIN)

    health = client.get(
        "/api/v1/insights/health", headers=auth_headers(admin), params={"today": str(TODAY)}
    ).json()

    assert len(health["overdue_tasks"]) == 1


def test_workload_counts_only_tasks_of_the_viewed_project(client, team):
    other = client.post(
        "/api/v1/projects", headers=team["h"]["lead"], json={"name": "Autre projet"}
    ).json()
    client.put(
        f"/api/v1/projects/{other['id']}/members/{team['contributor'].id}",
        headers=team["h"]["lead"],
        json={"role": "contributor"},
    )
    client.post(
        f"/api/v1/projects/{other['id']}/tasks",
        headers=team["h"]["lead"],
        json={"title": "Ailleurs", "assignee_id": str(team["contributor"].id)},
    )

    loads = client.get(
        f"/api/v1/projects/{team['project']['id']}/workload", headers=team["h"]["lead"]
    ).json()

    by_member = {load["member"]["id"]: load["open_tasks"] for load in loads}
    assert by_member[str(team["contributor"].id)] == 0
