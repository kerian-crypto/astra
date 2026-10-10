import uuid
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, ClientUploadQuota, CurrentClient, DbSession, Storage
from app.api.files import attached_file_response
from app.models.client_enums import ClientPermission, PaymentMethod
from app.schemas.client.billing import (
    ContractView,
    DeclarationView,
    InvoiceDetailView,
    InvoiceView,
)
from app.services.client import billing, documents

router = APIRouter(tags=["client-billing"])


@router.get("/invoices", response_model=list[InvoiceView])
def list_invoices(account: CurrentClient, db: DbSession) -> list[InvoiceView]:
    return [billing.invoice_view(db, i) for i in billing.list_invoices_for_client(db, account)]


@router.get("/invoices/{invoice_id}", response_model=InvoiceDetailView)
def read_invoice(invoice_id: uuid.UUID, account: CurrentClient, db: DbSession) -> InvoiceDetailView:
    invoice = billing.get_invoice_for_client(db, account, invoice_id)
    return billing.invoice_detail(db, account, invoice)


@router.get("/invoices/{invoice_id}/download", response_class=FileResponse)
def download_invoice(
    invoice_id: uuid.UUID, account: CurrentClient, db: DbSession, storage: Storage
) -> FileResponse:
    invoice = billing.get_invoice_for_client(db, account, invoice_id)
    documents.record_download(
        db,
        account,
        entity_type="invoice",
        entity_id=invoice.id,
        title=invoice.number,
        project_id=invoice.project_id,
    )
    return attached_file_response(storage, invoice)


@router.post(
    "/invoices/{invoice_id}/payment-declarations",
    response_model=DeclarationView,
    status_code=status.HTTP_201_CREATED,
    dependencies=[ClientUploadQuota],
)
def declare_payment(
    invoice_id: uuid.UUID,
    amount: Annotated[Decimal, Form(gt=0, max_digits=14, decimal_places=2)],
    paid_on: Annotated[date, Form()],
    method: Annotated[PaymentMethod, Form()],
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    reference: Annotated[str | None, Form(max_length=120)] = None,
    note: Annotated[str | None, Form(max_length=2_000)] = None,
    proof: Annotated[UploadFile | None, File()] = None,
) -> DeclarationView:
    """Déclare un paiement effectué hors de l'application (aucun paiement en ligne)."""
    invoice = billing.get_invoice_for_client(db, account, invoice_id)
    declaration = billing.declare_payment(
        db,
        storage,
        account,
        invoice,
        amount=amount,
        paid_on=paid_on,
        method=method,
        reference=reference,
        note=note,
        proof=(proof.filename or "preuve", proof.file) if proof else None,
        max_bytes=settings.MAX_CLIENT_UPLOAD_BYTES,
    )
    return billing.declaration_view(declaration)


@router.get("/payment-declarations", response_model=list[DeclarationView])
def list_declarations(account: CurrentClient, db: DbSession) -> list[DeclarationView]:
    return [billing.declaration_view(d) for d in billing.list_declarations_for_client(db, account)]


@router.get("/payment-declarations/{declaration_id}/proof", response_class=FileResponse)
def download_proof(
    declaration_id: uuid.UUID, account: CurrentClient, db: DbSession, storage: Storage
) -> FileResponse:
    declaration = billing.get_declaration_for_client(db, account, declaration_id)
    return attached_file_response(storage, declaration)


@router.get("/contracts", response_model=list[ContractView])
def list_contracts(account: CurrentClient, db: DbSession) -> list[ContractView]:
    show_amount = account.has_permission(ClientPermission.VIEW_FINANCIAL_DATA)
    return [
        billing.contract_view(db, c, show_amount=show_amount)
        for c in billing.list_contracts_for_client(db, account)
    ]


@router.get("/contracts/{contract_id}", response_model=ContractView)
def read_contract(contract_id: uuid.UUID, account: CurrentClient, db: DbSession) -> ContractView:
    contract = billing.get_contract_for_client(db, account, contract_id)
    return billing.contract_view(
        db, contract, show_amount=account.has_permission(ClientPermission.VIEW_FINANCIAL_DATA)
    )


@router.get("/contracts/{contract_id}/download", response_class=FileResponse)
def download_contract(
    contract_id: uuid.UUID, account: CurrentClient, db: DbSession, storage: Storage
) -> FileResponse:
    contract = billing.get_contract_for_client(db, account, contract_id)
    documents.record_download(
        db,
        account,
        entity_type="contract",
        entity_id=contract.id,
        title=contract.number,
        project_id=contract.project_id,
    )
    return attached_file_response(storage, contract)
