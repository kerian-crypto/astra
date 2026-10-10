"""Livrables, validations et documents partagés (§18-23, §61-62)."""

import io

from sqlalchemy import select

from app.models import ClientNotification, Notification
from tests.client_fixtures import API

PDF = b"%PDF-1.4\n%test\n"


def _create_deliverable(client, world, name="a", requires_validation=True) -> dict:
    project_id = world[name]["project"]["id"]
    response = client.post(
        f"{API}/projects/{project_id}/deliverables",
        headers=world["mh"],
        json={"title": "Maquette application", "requires_validation": requires_validation},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _publish(client, world, deliverable_id, content=PDF, link=None):
    data = {"notes": "Première version"}
    if link:
        data["link_url"] = link
    files = {"file": ("maquette.pdf", io.BytesIO(content), "application/pdf")} if content else None
    return client.post(
        f"{API}/deliverables/{deliverable_id}/versions", headers=world["mh"], data=data, files=files
    )


def test_draft_deliverable_is_invisible_to_client(client, client_world):
    deliverable = _create_deliverable(client, client_world)

    listing = client.get(f"{API}/client/deliverables", headers=client_world["a"]["h"]).json()
    direct = client.get(
        f"{API}/client/deliverables/{deliverable['id']}", headers=client_world["a"]["h"]
    )

    assert listing == []
    assert direct.status_code == 404


def test_publishing_notifies_client_and_requests_validation(client, client_world, db):
    deliverable = _create_deliverable(client, client_world)

    published = _publish(client, client_world, deliverable["id"])

    assert published.status_code == 201, published.text
    assert published.json()["status"] == "awaiting_validation"
    kinds = db.scalars(select(ClientNotification.kind)).all()
    assert "validation_required" in kinds
    detail = client.get(
        f"{API}/client/deliverables/{deliverable['id']}", headers=client_world["a"]["h"]
    ).json()
    assert detail["can_review"] is True
    assert detail["current_version"]["number"] == 1


def test_approval_is_traced_and_reaches_the_hub(client, client_world, db):
    deliverable = _create_deliverable(client, client_world)
    _publish(client, client_world, deliverable["id"])

    response = client.post(
        f"{API}/client/deliverables/{deliverable['id']}/reviews",
        headers=client_world["a"]["h"],
        data={"action": "approve", "comment": "Parfait"},
    )

    assert response.status_code == 201, response.text
    assert response.json()["status"] == "approved"
    hub_view = client.get(f"{API}/deliverables/{deliverable['id']}", headers=client_world["mh"])
    review = hub_view.json()["reviews"][0]
    assert review["action"] == "approve"
    assert review["reviewer_name"] == client_world["a"]["account"]["full_name"]
    assert review["version_number"] == 1
    assert "client_review" in db.scalars(select(Notification.kind)).all()


def test_change_request_requires_a_reason_and_accepts_attachment(client, client_world):
    deliverable = _create_deliverable(client, client_world)
    _publish(client, client_world, deliverable["id"])
    url = f"{API}/client/deliverables/{deliverable['id']}/reviews"

    empty = client.post(url, headers=client_world["a"]["h"], data={"action": "request_changes"})
    ok = client.post(
        url,
        headers=client_world["a"]["h"],
        data={"action": "request_changes", "reason": "Couleurs", "comment": "Plus de bleu"},
        files={"file": ("capture.png", io.BytesIO(b"\x89PNG\r\n\x1a\nxxxx"), "image/png")},
    )

    assert empty.status_code == 400
    assert ok.status_code == 201, ok.text
    assert ok.json()["status"] == "changes_requested"
    assert ok.json()["reviews"][0]["file"]["name"] == "capture.png"
    # Une nouvelle version relance la validation.
    again = _publish(client, client_world, deliverable["id"])
    assert again.json()["status"] == "awaiting_validation"
    assert again.json()["current_version"]["number"] == 2


def test_cannot_review_twice_or_without_permission(client, client_world, make_client_account):
    deliverable = _create_deliverable(client, client_world)
    _publish(client, client_world, deliverable["id"])
    url = f"{API}/client/deliverables/{deliverable['id']}/reviews"
    viewer = make_client_account(
        client_world["mh"], client_world["a"]["company"]["id"], permissions=["view_project"]
    )

    forbidden = client.post(url, headers=viewer["h"], data={"action": "approve"})
    client.post(url, headers=client_world["a"]["h"], data={"action": "approve"})
    twice = client.post(url, headers=client_world["a"]["h"], data={"action": "approve"})

    assert forbidden.status_code == 403
    assert twice.status_code == 409


def test_client_b_cannot_see_or_review_deliverable_a(client, client_world):
    deliverable = _create_deliverable(client, client_world)
    version = _publish(client, client_world, deliverable["id"]).json()["current_version"]
    b = client_world["b"]["h"]

    assert (
        client.get(f"{API}/client/deliverables/{deliverable['id']}", headers=b).status_code == 404
    )
    assert (
        client.post(
            f"{API}/client/deliverables/{deliverable['id']}/reviews",
            headers=b,
            data={"action": "approve"},
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"{API}/client/deliverables/{deliverable['id']}/versions/{version['id']}/download",
            headers=b,
        ).status_code
        == 404
    )


def test_download_version_and_link_only_version(client, client_world):
    deliverable = _create_deliverable(client, client_world, requires_validation=False)
    version = _publish(client, client_world, deliverable["id"]).json()["current_version"]

    download = client.get(
        f"{API}/client/deliverables/{deliverable['id']}/versions/{version['id']}/download",
        headers=client_world["a"]["h"],
    )
    link_only = _publish(
        client, client_world, deliverable["id"], content=None, link="https://app.example.com"
    )
    bad_link = _publish(
        client, client_world, deliverable["id"], content=None, link="javascript:alert(1)"
    )

    assert download.status_code == 200
    assert download.content == PDF
    assert "attachment" in download.headers["content-disposition"]
    assert link_only.json()["status"] == "published"
    assert link_only.json()["current_version"]["link_url"] == "https://app.example.com"
    assert bad_link.status_code == 400


def test_publishing_requires_client_link_and_lead(client, client_world, make_user, auth_headers):
    internal = client.post(
        f"{API}/projects", headers=client_world["mh"], json={"name": "Int"}
    ).json()
    deliverable = client.post(
        f"{API}/projects/{internal['id']}/deliverables",
        headers=client_world["mh"],
        json={"title": "Doc"},
    ).json()
    outsider = auth_headers(make_user())

    unlinked = _publish(client, client_world, deliverable["id"])
    foreign = client.get(f"{API}/deliverables/{deliverable['id']}", headers=outsider)

    assert unlinked.status_code == 409
    assert foreign.status_code == 404


# ---------- Documents partagés ----------


def _upload_document(client, world, name="a", title="Rapport mensuel", **extra):
    project_id = world[name]["project"]["id"]
    response = client.post(
        f"{API}/projects/{project_id}/documents",
        headers=world["mh"],
        data={"title": title, "kind": "minutes"},
        files={"file": ("rapport.pdf", io.BytesIO(PDF), "application/pdf")},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_documents_are_internal_until_shared(client, client_world):
    document = _upload_document(client, client_world)
    a = client_world["a"]["h"]

    assert document["visibility"] == "internal"
    assert client.get(f"{API}/client/documents", headers=a).json() == []
    assert (
        client.get(f"{API}/client/documents/{document['id']}/download", headers=a).status_code
        == 404
    )

    shared = client.put(
        f"{API}/documents/{document['id']}/visibility",
        headers=client_world["mh"],
        json={"visibility": "client"},
    )
    listing = client.get(f"{API}/client/documents", headers=a).json()

    assert shared.status_code == 200
    assert [d["id"] for d in listing] == [document["id"]]
    assert listing[0]["category"] == "report"
    assert (
        client.get(f"{API}/client/documents/{document['id']}/download", headers=a).status_code
        == 200
    )
    assert client.get(f"{API}/client/documents", headers=client_world["b"]["h"]).json() == []


def test_document_versions_show_latest_and_history(client, client_world):
    document = _upload_document(client, client_world)
    client.put(
        f"{API}/documents/{document['id']}/visibility",
        headers=client_world["mh"],
        json={"visibility": "client"},
    )

    v2 = client.post(
        f"{API}/documents/{document['id']}/versions",
        headers=client_world["mh"],
        files={"file": ("rapport-v2.pdf", io.BytesIO(PDF), "application/pdf")},
    )
    listing = client.get(f"{API}/client/documents", headers=client_world["a"]["h"]).json()
    history = client.get(
        f"{API}/client/documents/{v2.json()['id']}/versions", headers=client_world["a"]["h"]
    ).json()

    assert v2.status_code == 201, v2.text
    assert v2.json()["version"] == 2
    assert v2.json()["visibility"] == "client"
    assert [d["version"] for d in listing] == [2]
    assert [d["version"] for d in history] == [2, 1]


def test_general_documents_cannot_be_shared(client, client_world):
    general = client.post(
        f"{API}/documents",
        headers=client_world["mh"],
        data={"title": "Charte", "kind": "guide"},
        files={"file": ("charte.pdf", io.BytesIO(PDF), "application/pdf")},
    ).json()

    response = client.put(
        f"{API}/documents/{general['id']}/visibility",
        headers=client_world["mh"],
        json={"visibility": "client"},
    )

    assert response.status_code == 409


def test_project_status_change_reaches_client_timeline(client, client_world, db):
    project_id = client_world["a"]["project"]["id"]

    client.patch(
        f"{API}/projects/{project_id}",
        headers=client_world["mh"],
        json={"client_status": "waiting_client", "progress": 65},
    )
    view = client.get(f"{API}/client/projects/{project_id}", headers=client_world["a"]["h"]).json()
    timeline = client.get(
        f"{API}/client/projects/{project_id}/timeline", headers=client_world["a"]["h"]
    ).json()

    assert view["status"] == "waiting_client"
    assert view["progress"] == 65
    labels = [event["label"] for event in timeline]
    assert "Statut du projet : En attente de votre retour" in labels
    assert all("budget" not in event["label"].lower() for event in timeline)
    assert "project_updated" in db.scalars(select(ClientNotification.kind)).all()


def test_progress_defaults_to_completed_tasks(client, client_world):
    project_id = client_world["a"]["project"]["id"]
    mh = client_world["mh"]
    for title in ("Analyse", "Design"):
        client.post(f"{API}/projects/{project_id}/tasks", headers=mh, json={"title": title})
    task = client.get(f"{API}/projects/{project_id}/tasks", headers=mh).json()[0]
    client.patch(f"{API}/tasks/{task['id']}", headers=mh, json={"status": "done"})

    view = client.get(f"{API}/client/projects/{project_id}", headers=client_world["a"]["h"]).json()

    assert view["progress"] == 50
