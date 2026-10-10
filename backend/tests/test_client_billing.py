"""Factures, déclarations de paiement externes, vérification, contrats
(§26-33, §64). Aucun paiement n'est exécuté par l'application."""

import io
from datetime import date, timedelta

from sqlalchemy import select

from app.models import Notification
from tests.client_fixtures import API

PDF = b"%PDF-1.4\n%facture\n"


def _invoice(client, world, name="a", amount="1500000", **extra) -> dict:
    data = {"title": "Acompte", "amount": amount, "issue_date": date.today().isoformat(), **extra}
    response = client.post(
        f"{API}/clients/companies/{world[name]['company']['id']}/invoices",
        headers=world["mh"],
        data=data,
        files={"file": ("facture.pdf", io.BytesIO(PDF), "application/pdf")},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _declare(client, world, invoice_id, amount="1500000", name="a", proof=True, **extra):
    files = (
        {"proof": ("recu.jpg", io.BytesIO(b"\xff\xd8\xff\xe0xxxx"), "image/jpeg")}
        if proof
        else None
    )
    return client.post(
        f"{API}/client/invoices/{invoice_id}/payment-declarations",
        headers=world[name]["h"],
        data={
            "amount": amount,
            "paid_on": date.today().isoformat(),
            "method": "mobile_money",
            **extra,
        },
        files=files,
    )


def test_invoice_created_in_hub_is_visible_to_client(client, client_world):
    invoice = _invoice(
        client, client_world, due_date=(date.today() + timedelta(days=30)).isoformat()
    )

    listing = client.get(f"{API}/client/invoices", headers=client_world["a"]["h"]).json()
    download = client.get(
        f"{API}/client/invoices/{invoice['id']}/download", headers=client_world["a"]["h"]
    )
    notifications = client.get(f"{API}/client/notifications", headers=client_world["a"]["h"]).json()

    assert invoice["number"].startswith("AST-")
    assert listing[0]["payment_status"] == "unpaid"
    assert listing[0]["remaining_amount"] == "1500000.00"
    assert download.content == PDF
    assert any(n["kind"] == "invoice_created" for n in notifications)


def test_declaration_is_never_confirmed_automatically(client, client_world, db):
    invoice = _invoice(client, client_world)

    declaration = _declare(client, client_world, invoice["id"], reference="OM-123")
    detail = client.get(
        f"{API}/client/invoices/{invoice['id']}", headers=client_world["a"]["h"]
    ).json()

    assert declaration.status_code == 201, declaration.text
    assert declaration.json()["status"] == "declared"
    assert detail["payment_status"] == "payment_declared"
    assert detail["paid_amount"] == "0.00"
    assert "payment_declared" in db.scalars(select(Notification.kind)).all()


def test_review_confirm_and_reject_with_reason(client, client_world):
    invoice = _invoice(client, client_world, amount="1000")
    mh = client_world["mh"]
    first = _declare(client, client_world, invoice["id"], amount="400").json()

    started = client.post(
        f"{API}/clients/payment-declarations/{first['id']}/start-review", headers=mh
    )
    no_reason = client.post(
        f"{API}/clients/payment-declarations/{first['id']}/review",
        headers=mh,
        json={"confirm": False},
    )
    rejected = client.post(
        f"{API}/clients/payment-declarations/{first['id']}/review",
        headers=mh,
        json={"confirm": False, "rejection_reason": "La preuve transmise est illisible."},
    )

    assert started.json()["status"] == "under_review"
    assert no_reason.status_code == 422
    assert rejected.json()["status"] == "rejected"
    detail = client.get(f"{API}/client/invoices/{invoice['id']}", headers=client_world["a"]["h"])
    assert detail.json()["payment_status"] == "rejected"
    assert detail.json()["declarations"][0]["rejection_reason"].startswith("La preuve")

    second = _declare(client, client_world, invoice["id"], amount="400").json()
    client.post(
        f"{API}/clients/payment-declarations/{second['id']}/review",
        headers=mh,
        json={"confirm": True},
    )
    partial = client.get(f"{API}/client/invoices/{invoice['id']}", headers=client_world["a"]["h"])
    assert partial.json()["payment_status"] == "partially_confirmed"
    assert partial.json()["remaining_amount"] == "600.00"

    third = _declare(client, client_world, invoice["id"], amount="600").json()
    client.post(
        f"{API}/clients/payment-declarations/{third['id']}/review",
        headers=mh,
        json={"confirm": True},
    )
    paid = client.get(f"{API}/client/invoices/{invoice['id']}", headers=client_world["a"]["h"])
    assert paid.json()["payment_status"] == "confirmed"
    assert paid.json()["can_declare"] is False
    kinds = [
        n["kind"]
        for n in client.get(f"{API}/client/notifications", headers=client_world["a"]["h"]).json()
    ]
    assert {"payment_rejected", "payment_confirmed"} <= set(kinds)


def test_declaration_validation_rules(client, client_world):
    invoice = _invoice(client, client_world, amount="1000")
    tomorrow = (date.today() + timedelta(days=1)).isoformat()

    too_much = _declare(client, client_world, invoice["id"], amount="1001")
    future = _declare(client, client_world, invoice["id"], amount="10", paid_on=tomorrow)
    nothing = _declare(client, client_world, invoice["id"], amount="10", proof=False)
    reference_only = _declare(
        client, client_world, invoice["id"], amount="10", proof=False, reference="VIR-99"
    )

    assert too_much.status_code == 400
    assert future.status_code == 400
    assert nothing.status_code == 400
    assert reference_only.status_code == 201


def test_client_b_cannot_see_or_pay_invoice_a(client, client_world):
    invoice = _invoice(client, client_world)
    b = client_world["b"]["h"]

    assert client.get(f"{API}/client/invoices", headers=b).json() == []
    assert client.get(f"{API}/client/invoices/{invoice['id']}", headers=b).status_code == 404
    assert _declare(client, client_world, invoice["id"], name="b").status_code == 404
    assert (
        client.get(f"{API}/client/invoices/{invoice['id']}/download", headers=b).status_code == 404
    )


def test_declaring_requires_permission(client, client_world, make_client_account):
    invoice = _invoice(client, client_world)
    viewer = make_client_account(
        client_world["mh"], client_world["a"]["company"]["id"], permissions=["view_invoice"]
    )

    response = client.post(
        f"{API}/client/invoices/{invoice['id']}/payment-declarations",
        headers=viewer["h"],
        data={
            "amount": "10",
            "paid_on": date.today().isoformat(),
            "method": "cash",
            "reference": "x",
        },
    )

    assert response.status_code == 403


def test_cancelled_invoice_refuses_declarations(client, client_world):
    invoice = _invoice(client, client_world)
    client.patch(
        f"{API}/clients/invoices/{invoice['id']}",
        headers=client_world["mh"],
        json={"status": "cancelled"},
    )

    assert _declare(client, client_world, invoice["id"]).status_code == 409


def test_members_cannot_manage_billing(client, client_world, make_user, auth_headers):
    member = auth_headers(make_user())

    assert client.get(f"{API}/clients/invoices", headers=member).status_code == 403
    assert client.get(f"{API}/clients/payment-declarations", headers=member).status_code == 403


# ---------- Contrats ----------


def test_contract_visibility_and_financial_data(client, client_world, make_client_account):
    company_id = client_world["a"]["company"]["id"]
    mh = client_world["mh"]
    draft = client.post(
        f"{API}/clients/companies/{company_id}/contracts",
        headers=mh,
        json={"number": "CTR-001", "title": "Maintenance", "amount": "500000"},
    ).json()
    no_finance = make_client_account(mh, company_id, permissions=["view_contract"])

    assert client.get(f"{API}/client/contracts", headers=client_world["a"]["h"]).json() == []
    client.patch(f"{API}/clients/contracts/{draft['id']}", headers=mh, json={"status": "active"})

    full = client.get(f"{API}/client/contracts", headers=client_world["a"]["h"]).json()
    limited = client.get(f"{API}/client/contracts", headers=no_finance["h"]).json()

    assert full[0]["amount"] == "500000.00"
    assert limited[0]["amount"] is None
    assert client.get(f"{API}/client/contracts", headers=client_world["b"]["h"]).json() == []
    assert (
        client.get(
            f"{API}/client/contracts/{draft['id']}", headers=client_world["b"]["h"]
        ).status_code
        == 404
    )


def test_dashboard_lists_actions_and_counts(client, client_world):
    _invoice(client, client_world, due_date=(date.today() + timedelta(days=5)).isoformat())

    dashboard = client.get(f"{API}/client/dashboard", headers=client_world["a"]["h"]).json()

    assert dashboard["company"]["name"] == "Entreprise A"
    assert dashboard["active_projects"] == 1
    assert dashboard["pending_invoices"] == 1
    assert any(a["kind"] == "payment_due" for a in dashboard["actions"])
    assert dashboard["deadlines"][0]["kind"] == "invoice"


def test_cannot_declare_more_than_due_while_a_declaration_is_pending(client, client_world):
    invoice = _invoice(client, client_world, amount="1000")
    _declare(client, client_world, invoice["id"], amount="1000")

    again = _declare(client, client_world, invoice["id"], amount="1")
    detail = client.get(f"{API}/client/invoices/{invoice['id']}", headers=client_world["a"]["h"])

    assert again.status_code == 400
    assert detail.json()["can_declare"] is False
