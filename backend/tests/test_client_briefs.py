"""Inscription libre et questionnaire de cadrage (cahier des charges)."""

import io

from sqlalchemy import select

from app.models import Notification, Task
from tests.client_fixtures import API, CLIENT_PASSWORD, bearer

FULL_ANSWERS = {
    "company_name": "Sifter — de l'anglais to sift, filtrer",
    "whatsapp": "+237 699 86 03 60",
    "country": "Cameroun",
    "founded_year": 2026,
    "employees": 0,
    "sector": "Tertiaire",
    "activity": "Application Windows de dérushage vidéo intelligent.",
    "differentiation": "Innovation, simplicité, performance.",
    "flagship_offers": ["Sifter", "Suppression des silences"],
    "specific_requests": "Logo moderne évoquant l'IA et la vidéo.",
    "pitch": "Sifter révolutionne le dérushage vidéo.",
    "competitors": ["TimeBolt", "Descript", "CapCut"],
    "role_model": "Adobe, pour son identité forte.",
    "project_types": {"selected": ["visual_identity", "website"], "other": None},
    "project_description": "Créer l'identité visuelle de Sifter et son site.",
    "success_picture": "Devenir la référence du dérushage.",
    "why_now": "Le marché explose.",
    "consequences": "Perdre l'opportunité.",
    "stage": "launch",
    "sales_channels": {"selected": ["not_yet"], "other": None},
    "scope_elements": "Logiciel, site, réseaux.",
    "past_freelancers": "Non.",
    "why_us": "Identité intemporelle.",
    "objectives": "Une identité premium.",
    "target": "Créateurs de contenu.",
    "target_aspirations": "Gagner du temps.",
    "message": "Innovation et confiance.",
    "values": "Rapidité, simplicité, fiabilité.",
    "vision": "Nous croyons que créer doit être simple.",
    "mission": "Automatiser le dérushage.",
    "enemies": "Les tâches répétitives.",
    "weapons": "Un moteur FFmpeg performant.",
    "tone": "Moderne et rassurant.",
    "colors": {"selected": ["orange", "violet"], "other": None},
    "logo_types": {"selected": ["combination"], "other": None},
    "words_to_evoke": ["Rapidité", "Simplicité", "Performance"],
    "slogan": "Moins de clics. Plus de création.",
    "supports": ["Interface du logiciel", "Site web officiel", "Cartes de visite"],
    "deadline": "2027-08-03",
}


def _register(client, email="hermann@example.com"):
    return client.post(
        f"{API}/client/auth/register",
        json={
            "company_name": "Sifter",
            "full_name": "Hermann Bonns",
            "email": email,
            "phone": "+237 699 86 03 60",
            "country": "Cameroun",
            "password": CLIENT_PASSWORD,
        },
    )


def test_registration_creates_an_isolated_company_and_logs_in(client, client_world, db):
    response = _register(client)

    assert response.status_code == 201, response.text
    h = bearer(response.json()["access_token"])
    me = client.get(f"{API}/client/me", headers=h).json()
    assert me["company"]["name"] == "Sifter"
    assert "submit_brief" in me["permissions"]
    assert client.get(f"{API}/client/projects", headers=h).json() == []
    other = client_world["a"]["project"]["id"]
    assert client.get(f"{API}/client/projects/{other}", headers=h).status_code == 404
    assert client.get(f"{API}/client/dashboard", headers=h).json()["needs_onboarding"] is True
    assert "client_signup" in db.scalars(select(Notification.kind)).all()


def test_registration_refuses_existing_email(client, client_world):
    _register(client)

    duplicate = _register(client)
    invited = _register(client, email=client_world["a"]["account"]["email"])

    assert duplicate.status_code == invited.status_code == 409


def test_questionnaire_lists_all_sections(client):
    questionnaire = client.get(f"{API}/client/briefs/questionnaire").json()

    ids = [s["id"] for s in questionnaire["sections"]]
    assert ids == ["company", "project", "goals", "brand", "visual", "delivery"]
    colors = next(
        q for s in questionnaire["sections"] for q in s["questions"] if q["id"] == "colors"
    )
    assert colors["max_items"] == 3 and colors["allow_other"] is True


def test_brief_draft_save_validate_files_and_submit(client, client_world, db):
    h = bearer(_register(client).json()["access_token"])
    brief = client.post(f"{API}/client/briefs", headers=h).json()
    assert brief["answers"]["company_name"] == "Sifter"  # prérempli
    again = client.post(f"{API}/client/briefs", headers=h).json()
    assert again["id"] == brief["id"]  # le brouillon est repris
    url = f"{API}/client/briefs/{brief['id']}"

    bad = client.patch(url, headers=h, json={"answers": {"colors": {"selected": ["pink"]}}})
    too_many = client.patch(
        url,
        headers=h,
        json={"answers": {"colors": {"selected": ["red", "blue", "green", "black"]}}},
    )
    early = client.post(f"{url}/submit", headers=h)
    saved = client.patch(
        url, headers=h, json={"answers": FULL_ANSWERS, "current_section": "delivery"}
    )
    upload = client.post(
        f"{url}/files",
        headers=h,
        data={"question_id": "inspiration_files"},
        files={"file": ("logo.png", io.BytesIO(b"\x89PNG\r\n\x1a\nxxxx"), "image/png")},
    )
    wrong_question = client.post(
        f"{url}/files",
        headers=h,
        data={"question_id": "pitch"},
        files={"file": ("logo.png", io.BytesIO(b"\x89PNG\r\n\x1a\nxxxx"), "image/png")},
    )
    submitted = client.post(f"{url}/submit", headers=h)
    locked = client.patch(url, headers=h, json={"answers": {"slogan": "x"}})

    assert bad.status_code == too_many.status_code == 400
    assert early.status_code == 400 and "obligatoires" in early.json()["detail"]
    assert saved.json()["missing_required"] == []
    assert saved.json()["current_section"] == "delivery"
    assert (
        upload.status_code == 201
        and upload.json()["files"][0]["question_id"] == "inspiration_files"
    )
    assert wrong_question.status_code == 400
    assert submitted.json()["status"] == "submitted"
    assert locked.status_code == 409
    assert "client_brief" in db.scalars(select(Notification.kind)).all()


def test_hub_reviews_brief_and_converts_it_into_a_project(client, client_world, db):
    h = bearer(_register(client).json()["access_token"])
    brief = client.post(f"{API}/client/briefs", headers=h).json()
    url = f"{API}/client/briefs/{brief['id']}"
    client.patch(url, headers=h, json={"answers": FULL_ANSWERS})
    mh = client_world["mh"]

    hidden_draft = client.get(f"{API}/clients/briefs/{brief['id']}", headers=mh)
    client.post(f"{url}/submit", headers=h)
    hub = client.get(f"{API}/clients/briefs/{brief['id']}", headers=mh).json()

    assert hidden_draft.status_code == 404
    phases = [p["name"] for p in hub["proposed_plan"]["phases"]]
    assert phases[0] == "Cadrage" and phases[-1] == "Livraison"
    assert {"Création du logo", "Charte graphique", "Supports de communication", "Site web"} <= set(
        phases
    )
    titles = [t["title"] for p in hub["proposed_plan"]["phases"] for t in p["tasks"]]
    assert "Déclinaison : Cartes de visite" in titles
    assert "Analyse des concurrents" in titles
    assert hub["proposed_plan"]["due_date"] == "2027-08-03"

    converted = client.post(f"{API}/clients/briefs/{brief['id']}/convert", headers=mh, json={})
    assert converted.status_code == 200, converted.text
    project_id = converted.json()["project_id"]
    assert converted.json()["status"] == "converted"
    client_projects = client.get(f"{API}/client/projects", headers=h).json()
    assert [p["id"] for p in client_projects] == [project_id]
    tasks = db.scalars(select(Task.title).where(Task.project_id == project_id)).all()
    assert len(tasks) >= 15
    # Les tâches internes ne sont jamais exposées au client.
    view = client.get(f"{API}/client/projects/{project_id}", headers=h).json()
    assert "tasks" not in view and "phases" not in view
    assert (
        client.post(f"{API}/clients/briefs/{brief['id']}/convert", headers=mh, json={}).status_code
        == 409
    )


def test_briefs_are_isolated_and_reserved_to_managers(
    client, client_world, make_user, auth_headers
):
    h = bearer(_register(client).json()["access_token"])
    brief = client.post(f"{API}/client/briefs", headers=h).json()

    other_client = client.get(f"{API}/client/briefs/{brief['id']}", headers=client_world["a"]["h"])
    member = client.get(f"{API}/clients/briefs", headers=auth_headers(make_user()))

    assert other_client.status_code == 404
    assert member.status_code == 403
