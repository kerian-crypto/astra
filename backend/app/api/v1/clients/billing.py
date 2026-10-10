import uuid
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, CurrentUser, DbSession, Storage, UploadQuota
from app.api.files import attached_file_response
from app.models.client_enums import PaymentDeclarationStatus
from app.schemas.client.billing import (
    ContractCreate,
    ContractHub,
    ContractUpdate,
    DeclarationHub,
    DeclarationReview,
    InvoiceHub,
    InvoiceUpdate,
)
from app.services.client import billing

router = APIRouter(prefix="/clients", tags=["clients"])

CurrencyForm = Annotated[str, Form(min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")]


@router.get("/invoices", response_model=list[InvoiceHub])
def list_invoices(
    user: CurrentUser, db: DbSession, company_id: uuid.UUID | None = None, open_only: bool = False
) -> list[InvoiceHub]:
    return [
        billing.invoice_hub(db, i)
        for i in billing.list_invoices_for_hub(db, user, company_id=company_id, open_only=open_only)
    ]


@router.post(
    "/companies/{company_id}/invoices",
    response_model=InvoiceHub,
    status_code=status.HTTP_201_CREATED,
    dependencies=[UploadQuota],
)
def create_invoice(
    company_id: uuid.UUID,
    title: Annotated[str, Form(min_length=1, max_length=200)],
    amount: Annotated[Decimal, Form(gt=0, max_digits=14, decimal_places=2)],
    issue_date: Annotated[date, Form()],
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
    currency: CurrencyForm = "XOF",
    due_date: Annotated[date | None, Form()] = None,
    project_id: Annotated[uuid.UUID | None, Form()] = None,
    file: Annotated[UploadFile | None, File()] = None,
) -> InvoiceHub:
    invoice = billing.create_invoice(
        db,
        storage,
        user,
        company_id=company_id,
        title=title,
        amount=amount,
        currency=currency,
        issue_date=issue_date,
        due_date=due_date,
        project_id=project_id,
        upload=(file.filename or "facture.pdf", file.file) if file else None,
        max_bytes=settings.MAX_UPLOAD_BYTES,
    )
    return billing.invoice_hub(db, invoice)


@router.get("/invoices/{invoice_id}", response_model=InvoiceHub)
def read_invoice(invoice_id: uuid.UUID, user: CurrentUser, db: DbSession) -> InvoiceHub:
    return billing.invoice_hub(db, billing.get_invoice_for_hub(db, user, invoice_id))


@router.patch("/invoices/{invoice_id}", response_model=InvoiceHub)
def update_invoice(
    invoice_id: uuid.UUID, body: InvoiceUpdate, user: CurrentUser, db: DbSession
) -> InvoiceHub:
    invoice = billing.get_invoice_for_hub(db, user, invoice_id)
    return billing.invoice_hub(db, billing.update_invoice(db, user, invoice, body))


@router.put("/invoices/{invoice_id}/file", response_model=InvoiceHub, dependencies=[UploadQuota])
def set_invoice_file(
    invoice_id: uuid.UUID,
    file: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
) -> InvoiceHub:
    invoice = billing.get_invoice_for_hub(db, user, invoice_id)
    billing.set_file(
        db,
        storage,
        user,
        invoice,
        file.filename or "facture.pdf",
        file.file,
        settings.MAX_UPLOAD_BYTES,
    )
    return billing.invoice_hub(db, invoice)


@router.get("/invoices/{invoice_id}/download", response_class=FileResponse)
def download_invoice(
    invoice_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    return attached_file_response(storage, billing.get_invoice_for_hub(db, user, invoice_id))


@router.get("/payment-declarations", response_model=list[DeclarationHub])
def list_declarations(
    user: CurrentUser,
    db: DbSession,
    status: PaymentDeclarationStatus | None = None,
    pending_only: bool = False,
) -> list[DeclarationHub]:
    return [
        billing.declaration_hub(db, d)
        for d in billing.list_declarations_for_hub(
            db, user, status=status, pending_only=pending_only
        )
    ]


@router.get("/payment-declarations/{declaration_id}", response_model=DeclarationHub)
def read_declaration(declaration_id: uuid.UUID, user: CurrentUser, db: DbSession) -> DeclarationHub:
    return billing.declaration_hub(db, billing.get_declaration_for_hub(db, user, declaration_id))


@router.post("/payment-declarations/{declaration_id}/start-review", response_model=DeclarationHub)
def start_review(declaration_id: uuid.UUID, user: CurrentUser, db: DbSession) -> DeclarationHub:
    declaration = billing.get_declaration_for_hub(db, user, declaration_id)
    return billing.declaration_hub(db, billing.start_review(db, user, declaration))


@router.post("/payment-declarations/{declaration_id}/review", response_model=DeclarationHub)
def review_declaration(
    declaration_id: uuid.UUID, body: DeclarationReview, user: CurrentUser, db: DbSession
) -> DeclarationHub:
    """Confirmer ou refuser (motif obligatoire) un paiement déclaré."""
    declaration = billing.get_declaration_for_hub(db, user, declaration_id)
    return billing.declaration_hub(db, billing.review_declaration(db, user, declaration, body))


@router.get("/payment-declarations/{declaration_id}/proof", response_class=FileResponse)
def download_proof(
    declaration_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    return attached_file_response(
        storage, billing.get_declaration_for_hub(db, user, declaration_id)
    )


@router.get("/contracts", response_model=list[ContractHub])
def list_contracts(
    user: CurrentUser, db: DbSession, company_id: uuid.UUID | None = None
) -> list[ContractHub]:
    return [
        billing.contract_hub(db, c)
        for c in billing.list_contracts_for_hub(db, user, company_id=company_id)
    ]


@router.post(
    "/companies/{company_id}/contracts",
    response_model=ContractHub,
    status_code=status.HTTP_201_CREATED,
)
def create_contract(
    company_id: uuid.UUID, body: ContractCreate, user: CurrentUser, db: DbSession
) -> ContractHub:
    return billing.contract_hub(db, billing.create_contract(db, user, company_id, body))


@router.get("/contracts/{contract_id}", response_model=ContractHub)
def read_contract(contract_id: uuid.UUID, user: CurrentUser, db: DbSession) -> ContractHub:
    return billing.contract_hub(db, billing.get_contract_for_hub(db, user, contract_id))


@router.patch("/contracts/{contract_id}", response_model=ContractHub)
def update_contract(
    contract_id: uuid.UUID, body: ContractUpdate, user: CurrentUser, db: DbSession
) -> ContractHub:
    contract = billing.get_contract_for_hub(db, user, contract_id)
    return billing.contract_hub(db, billing.update_contract(db, user, contract, body))


@router.put("/contracts/{contract_id}/file", response_model=ContractHub, dependencies=[UploadQuota])
def set_contract_file(
    contract_id: uuid.UUID,
    file: Annotated[UploadFile, File()],
    user: CurrentUser,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
) -> ContractHub:
    contract = billing.get_contract_for_hub(db, user, contract_id)
    billing.set_file(
        db,
        storage,
        user,
        contract,
        file.filename or "contrat.pdf",
        file.file,
        settings.MAX_UPLOAD_BYTES,
    )
    return billing.contract_hub(db, contract)


@router.get("/contracts/{contract_id}/download", response_class=FileResponse)
def download_contract(
    contract_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    return attached_file_response(storage, billing.get_contract_for_hub(db, user, contract_id))
