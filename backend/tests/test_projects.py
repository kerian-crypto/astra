import pytest

from app.models.enums import AccessLevel

PROJECTS = "/api/v1/projects"


@pytest.fixture
def project_with_team(client, make_user, auth_headers):
    """Projet créé par un manager (lead), avec un contributeur et un lecteur."""
    lead = make_user(AccessLevel.MANAGER)
    contributor, viewer, outsider = make_user(), make_user(), make_user()
    headers = auth_headers(lead)
    project = client.post(
        PROJECTS, headers=headers, json={"name": "MarketCM V2", "priority": "high"}
    ).json()
    for member, role in ((contributor, "contributor"), (viewer, "viewer")):
        client.put(
            f"{PROJECTS}/{project['id']}/members/{member.id}", headers=headers, json={"role": role}
        )
    return {
        "project": project,
        "lead": lead,
        "contributor": contributor,
        "viewer": viewer,
        "outsider": outsider,
    }


def test_manager_creates_project_and_becomes_lead(client, make_user, auth_headers):
    manager = make_user(AccessLevel.MANAGER)

    response = client.post(
        PROJECTS,
        headers=auth_headers(manager),
        json={"name": "Astra Hub", "objective": "Créer le MVP", "budget": "1500.50"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "idea"
    assert body["my_role"] == "lead"
    assert [(m["user"]["id"], m["role"]) for m in body["members"]] == [(str(manager.id), "lead")]


def test_creator_can_designate_another_lead(client, make_user, auth_headers):
    manager, lead = make_user(AccessLevel.MANAGER), make_user()

    body = client.post(
        PROJECTS, headers=auth_headers(manager), json={"name": "P", "lead_id": str(lead.id)}
    ).json()

    roles = {m["user"]["id"]: m["role"] for m in body["members"]}
    assert roles == {str(lead.id): "lead", str(manager.id): "contributor"}


def test_plain_member_cannot_create_project(client, make_user, auth_headers):
    member = make_user()

    response = client.post(PROJECTS, headers=auth_headers(member), json={"name": "P"})

    assert response.status_code == 403


def test_project_list_only_shows_projects_the_member_belongs_to(
    client, auth_headers, project_with_team
):
    team = project_with_team

    member_view = client.get(PROJECTS, headers=auth_headers(team["viewer"])).json()
    outsider_view = client.get(PROJECTS, headers=auth_headers(team["outsider"])).json()

    assert [p["id"] for p in member_view] == [team["project"]["id"]]
    assert outsider_view == []


def test_admin_sees_every_project(client, make_user, auth_headers, project_with_team):
    admin = make_user(AccessLevel.ADMIN)

    listed = client.get(PROJECTS, headers=auth_headers(admin)).json()
    detail = client.get(
        f"{PROJECTS}/{project_with_team['project']['id']}", headers=auth_headers(admin)
    )

    assert len(listed) == 1
    assert detail.json()["my_role"] == "lead"


def test_outsider_gets_404_not_403_on_project(client, auth_headers, project_with_team):
    """Ne pas révéler l'existence d'un projet auquel on n'a pas accès."""
    project_id = project_with_team["project"]["id"]
    headers = auth_headers(project_with_team["outsider"])

    assert client.get(f"{PROJECTS}/{project_id}", headers=headers).status_code == 404
    assert (
        client.patch(f"{PROJECTS}/{project_id}", headers=headers, json={"name": "x"}).status_code
        == 404
    )


def test_project_list_filters_by_status(client, auth_headers, project_with_team):
    headers = auth_headers(project_with_team["lead"])

    active = client.get(f"{PROJECTS}?status=active", headers=headers).json()
    idea = client.get(f"{PROJECTS}?status=idea", headers=headers).json()

    assert active == []
    assert len(idea) == 1


@pytest.mark.parametrize(
    ("role", "expected"),
    [("lead", 200), ("contributor", 403), ("viewer", 403)],
)
def test_only_lead_can_update_project(client, auth_headers, project_with_team, role, expected):
    project_id = project_with_team["project"]["id"]

    response = client.patch(
        f"{PROJECTS}/{project_id}",
        headers=auth_headers(project_with_team[role]),
        json={"status": "planning"},
    )

    assert response.status_code == expected


def test_project_update_rejects_null_name(client, auth_headers, project_with_team):
    project_id = project_with_team["project"]["id"]

    response = client.patch(
        f"{PROJECTS}/{project_id}",
        headers=auth_headers(project_with_team["lead"]),
        json={"name": None},
    )

    assert response.status_code == 422


def test_contributor_cannot_add_members(client, auth_headers, project_with_team):
    team = project_with_team

    response = client.put(
        f"{PROJECTS}/{team['project']['id']}/members/{team['outsider'].id}",
        headers=auth_headers(team["contributor"]),
        json={"role": "viewer"},
    )

    assert response.status_code == 403


def test_lead_adds_member_who_then_gains_access(client, auth_headers, project_with_team):
    team = project_with_team
    project_id = team["project"]["id"]

    added = client.put(
        f"{PROJECTS}/{project_id}/members/{team['outsider'].id}",
        headers=auth_headers(team["lead"]),
        json={"role": "viewer"},
    )
    access = client.get(f"{PROJECTS}/{project_id}", headers=auth_headers(team["outsider"]))

    assert added.status_code == 200
    assert access.status_code == 200
    assert access.json()["my_role"] == "viewer"


def test_removed_member_loses_access(client, auth_headers, project_with_team):
    team = project_with_team
    project_id = team["project"]["id"]

    removed = client.delete(
        f"{PROJECTS}/{project_id}/members/{team['viewer'].id}", headers=auth_headers(team["lead"])
    )
    access = client.get(f"{PROJECTS}/{project_id}", headers=auth_headers(team["viewer"]))

    assert removed.status_code == 204
    assert access.status_code == 404


def test_last_lead_cannot_be_removed_or_demoted(client, auth_headers, project_with_team):
    team = project_with_team
    project_id = team["project"]["id"]
    headers = auth_headers(team["lead"])
    lead_url = f"{PROJECTS}/{project_id}/members/{team['lead'].id}"

    assert client.delete(lead_url, headers=headers).status_code == 409
    assert client.put(lead_url, headers=headers, json={"role": "viewer"}).status_code == 409


def test_lead_can_step_down_once_another_lead_exists(client, auth_headers, project_with_team):
    team = project_with_team
    project_id = team["project"]["id"]
    headers = auth_headers(team["lead"])

    client.put(
        f"{PROJECTS}/{project_id}/members/{team['contributor'].id}",
        headers=headers,
        json={"role": "lead"},
    )
    response = client.put(
        f"{PROJECTS}/{project_id}/members/{team['lead'].id}",
        headers=headers,
        json={"role": "viewer"},
    )

    assert response.status_code == 200


def test_cannot_add_inactive_member(client, db, auth_headers, project_with_team):
    team = project_with_team
    team["outsider"].is_active = False
    db.commit()

    response = client.put(
        f"{PROJECTS}/{team['project']['id']}/members/{team['outsider'].id}",
        headers=auth_headers(team["lead"]),
        json={"role": "viewer"},
    )

    assert response.status_code == 404


def test_lead_deletes_project(client, auth_headers, project_with_team):
    team = project_with_team
    project_id = team["project"]["id"]

    forbidden = client.delete(f"{PROJECTS}/{project_id}", headers=auth_headers(team["contributor"]))
    deleted = client.delete(f"{PROJECTS}/{project_id}", headers=auth_headers(team["lead"]))
    gone = client.get(f"{PROJECTS}/{project_id}", headers=auth_headers(team["lead"]))

    assert forbidden.status_code == 403
    assert deleted.status_code == 204
    assert gone.status_code == 404
