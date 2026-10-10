import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.client_enums import (
    ContractStatus,
    InvoicePaymentStatus,
    InvoiceStatus,
    PaymentDeclarationStatus,
    PaymentMethod,
)
from app.schemas.client.common import AttachedFile
from app.schemas.common import PartialUpdate

Amount = Field(gt=0, max_digits=14, decimal_places=2)
Currency = Field(default="XOF", min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")


class DeclarationView(BaseModel):
    id: uuid.UUID
    invoice_id: uuid.UUID
    invoice_number: str
    amount: Decimal
    currency: str
    paid_on: date
    method: PaymentMethod
    reference: str | None
    note: str | None
    status: PaymentDeclarationStatus
    confirmed_amount: Decimal | None
    rejection_reason: str | None
    proof: AttachedFile | None
    declared_by_name: str | None
    reviewed_at: datetime | None
    created_at: datetime


class InvoiceView(BaseModel):
    id: uuid.UUID
    number: str
    title: str
    project_id: uuid.UUID | None
    project_name: str | None
    amount: Decimal
    currency: str
    issue_date: date
    due_date: date | None
    paid_amount: Decimal
    remaining_amount: Decimal
    status: InvoiceStatus
    payment_status: InvoicePaymentStatus
    is_overdue: bool
    file: AttachedFile | None


class InvoiceDetailView(InvoiceView):
    declarations: list[DeclarationView]
    can_declare: bool


class DeclarationHub(DeclarationView):
    company_id: uuid.UUID
    company_name: str
    reviewed_by_name: str | None


class InvoiceHub(InvoiceDetailView):
    company_id: uuid.UUID
    company_name: str
    created_at: datetime


class InvoiceUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"title", "status"})

    title: str | None = Field(default=None, min_length=1, max_length=200)
    due_date: date | None = None
    status: InvoiceStatus | None = None


class DeclarationReview(BaseModel):
    """Décision d'Astra sur un paiement déclaré (§30-31)."""

    model_config = ConfigDict(extra="forbid")

    confirm: bool
    # Montant réellement reçu ; par défaut celui déclaré.
    confirmed_amount: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    # Obligatoire en cas de refus : le client doit savoir quoi corriger.
    rejection_reason: str | None = Field(default=None, max_length=2_000)

    @model_validator(mode="after")
    def reason_when_rejected(self) -> "DeclarationReview":
        if not self.confirm and not (self.rejection_reason or "").strip():
            raise ValueError("Le motif du refus est obligatoire.")
        return self


class ContractView(BaseModel):
    id: uuid.UUID
    number: str
    title: str
    project_id: uuid.UUID | None
    project_name: str | None
    services: str | None
    # Nul si le compte n'a pas accès aux données financières.
    amount: Decimal | None
    currency: str
    start_date: date | None
    end_date: date | None
    renewal_terms: str | None
    payment_schedule: str | None
    status: ContractStatus
    file: AttachedFile | None


class ContractHub(ContractView):
    company_id: uuid.UUID
    company_name: str
    created_at: datetime


class ContractCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    number: str = Field(min_length=1, max_length=40)
    title: str = Field(min_length=1, max_length=200)
    project_id: uuid.UUID | None = None
    services: str | None = Field(default=None, max_length=10_000)
    amount: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    currency: str = Currency
    start_date: date | None = None
    end_date: date | None = None
    renewal_terms: str | None = Field(default=None, max_length=300)
    payment_schedule: str | None = Field(default=None, max_length=5_000)
    status: ContractStatus = ContractStatus.DRAFT


class ContractUpdate(PartialUpdate):
    model_config = ConfigDict(extra="forbid")
    NON_NULLABLE = frozenset({"title", "status", "currency"})

    title: str | None = Field(default=None, min_length=1, max_length=200)
    project_id: uuid.UUID | None = None
    services: str | None = Field(default=None, max_length=10_000)
    amount: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    currency: str | None = Field(default=None, min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")
    start_date: date | None = None
    end_date: date | None = None
    renewal_terms: str | None = Field(default=None, max_length=300)
    payment_schedule: str | None = Field(default=None, max_length=5_000)
    status: ContractStatus | None = None
