"""Factures, déclarations de paiement externes et contrats (§26-33).

Aucun paiement n'est exécuté par l'application (§27) : le client déclare un
paiement fait ailleurs, joint une preuve, et un membre d'Astra le vérifie.
"""

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import BinaryIO

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.storage import LocalFileStorage
from app.models import (
    ClientAccount,
    ClientCompany,
    Contract,
    Invoice,
    PaymentDeclaration,
    Project,
    User,
)
from app.models.client_enums import (
    ClientNotificationKind,
    ClientPermission,
    ContractStatus,
    InvoicePaymentStatus,
    InvoiceStatus,
    PaymentDeclarationStatus,
    PaymentMethod,
)
from app.models.enums import NotificationKind
from app.schemas.client.billing import (
    ContractCreate,
    ContractHub,
    ContractUpdate,
    ContractView,
    DeclarationHub,
    DeclarationReview,
    DeclarationView,
    InvoiceDetailView,
    InvoiceHub,
    InvoiceUpdate,
    InvoiceView,
)
from app.schemas.client.common import attached_file
from app.services import activity_service, notification_service
from app.services.client import access, audit, conversations, files, notifications, numbering
from app.services.client.hub_access import require_client_manager
from app.services.client.labels import format_money
from app.services.errors import ConflictError, NotFoundError, ServiceError

INVOICE_NOT_FOUND = "Facture introuvable."
CONTRACT_NOT_FOUND = "Contrat introuvable."
DECLARATION_NOT_FOUND = "Déclaration introuvable."
PENDING = frozenset({PaymentDeclarationStatus.DECLARED, PaymentDeclarationStatus.UNDER_REVIEW})
ZERO = Decimal("0.00")


# ---------- Calculs ----------


def paid_amount(invoice: Invoice) -> Decimal:
    """Somme des paiements confirmés par Astra (jamais saisie à la main)."""
    return sum(
        (
            d.confirmed_amount if d.confirmed_amount is not None else d.amount
            for d in invoice.declarations
            if d.status == PaymentDeclarationStatus.CONFIRMED
        ),
        ZERO,
    )


def remaining_amount(invoice: Invoice) -> Decimal:
    return max(invoice.amount - paid_amount(invoice), ZERO)


def declarable_amount(invoice: Invoice) -> Decimal:
    """Reste à payer moins les paiements déjà déclarés en attente de
    vérification : on ne déclare jamais plus que le montant dû."""
    pending = sum((d.amount for d in invoice.declarations if d.status in PENDING), ZERO)
    return max(remaining_amount(invoice) - pending, ZERO)


def payment_status(invoice: Invoice) -> InvoicePaymentStatus:
    paid = paid_amount(invoice)
    statuses = {d.status for d in invoice.declarations}
    if paid >= invoice.amount:
        return InvoicePaymentStatus.CONFIRMED
    if PaymentDeclarationStatus.UNDER_REVIEW in statuses:
        return InvoicePaymentStatus.UNDER_REVIEW
    if PaymentDeclarationStatus.DECLARED in statuses:
        return InvoicePaymentStatus.PAYMENT_DECLARED
    if paid > ZERO:
        return InvoicePaymentStatus.PARTIALLY_CONFIRMED
    latest = invoice.declarations[0] if invoice.declarations else None
    if latest is not None and latest.status == PaymentDeclarationStatus.REJECTED:
        return InvoicePaymentStatus.REJECTED
    return InvoicePaymentStatus.UNPAID


def is_open(invoice: Invoice) -> bool:
    """Facture émise et pas entièrement réglée."""
    return invoice.status == InvoiceStatus.ISSUED and payment_status(invoice) != (
        InvoicePaymentStatus.CONFIRMED
    )


def _project_name(db: Session, project_id: uuid.UUID | None) -> str | None:
    project = db.get(Project, project_id) if project_id else None
    return project.name if project else None


# ---------- Représentations ----------


def declaration_view(declaration: PaymentDeclaration) -> DeclarationView:
    return DeclarationView(
        id=declaration.id,
        invoice_id=declaration.invoice_id,
        invoice_number=declaration.invoice.number,
        amount=declaration.amount,
        currency=declaration.invoice.currency,
        paid_on=declaration.paid_on,
        method=declaration.method,
        reference=declaration.reference,
        note=declaration.note,
        status=declaration.status,
        confirmed_amount=declaration.confirmed_amount,
        rejection_reason=declaration.rejection_reason,
        proof=attached_file(declaration),
        declared_by_name=declaration.declared_by.full_name if declaration.declared_by else None,
        reviewed_at=declaration.reviewed_at,
        created_at=declaration.created_at,
    )


def declaration_hub(db: Session, declaration: PaymentDeclaration) -> DeclarationHub:
    company = db.get(ClientCompany, declaration.company_id)
    return DeclarationHub(
        **declaration_view(declaration).model_dump(),
        company_id=declaration.company_id,
        company_name=company.name,
        reviewed_by_name=declaration.reviewed_by.full_name if declaration.reviewed_by else None,
    )


def invoice_view(db: Session, invoice: Invoice) -> InvoiceView:
    status = payment_status(invoice)
    overdue = (
        invoice.status == InvoiceStatus.ISSUED
        and status != InvoicePaymentStatus.CONFIRMED
        and invoice.due_date is not None
        and invoice.due_date < date.today()
    )
    return InvoiceView(
        id=invoice.id,
        number=invoice.number,
        title=invoice.title,
        project_id=invoice.project_id,
        project_name=_project_name(db, invoice.project_id),
        amount=invoice.amount,
        currency=invoice.currency,
        issue_date=invoice.issue_date,
        due_date=invoice.due_date,
        paid_amount=paid_amount(invoice),
        remaining_amount=remaining_amount(invoice),
        status=invoice.status,
        payment_status=status,
        is_overdue=overdue,
        file=attached_file(invoice),
    )


def invoice_detail(db: Session, account: ClientAccount, invoice: Invoice) -> InvoiceDetailView:
    return InvoiceDetailView(
        **invoice_view(db, invoice).model_dump(),
        declarations=[declaration_view(d) for d in invoice.declarations],
        can_declare=is_open(invoice)
        and declarable_amount(invoice) > ZERO
        and account.has_permission(ClientPermission.SUBMIT_PAYMENT_PROOF),
    )


def invoice_hub(db: Session, invoice: Invoice) -> InvoiceHub:
    company = db.get(ClientCompany, invoice.company_id)
    return InvoiceHub(
        **invoice_view(db, invoice).model_dump(),
        declarations=[declaration_view(d) for d in invoice.declarations],
        can_declare=False,
        company_id=invoice.company_id,
        company_name=company.name,
        created_at=invoice.created_at,
    )


def contract_view(db: Session, contract: Contract, *, show_amount: bool) -> ContractView:
    return ContractView(
        id=contract.id,
        number=contract.number,
        title=contract.title,
        project_id=contract.project_id,
        project_name=_project_name(db, contract.project_id),
        services=contract.services,
        amount=contract.amount if show_amount else None,
        currency=contract.currency,
        start_date=contract.start_date,
        end_date=contract.end_date,
        renewal_terms=contract.renewal_terms,
        payment_schedule=contract.payment_schedule,
        status=contract.status,
        file=attached_file(contract),
    )


def contract_hub(db: Session, contract: Contract) -> ContractHub:
    company = db.get(ClientCompany, contract.company_id)
    return ContractHub(
        **contract_view(db, contract, show_amount=True).model_dump(),
        company_id=contract.company_id,
        company_name=company.name,
        created_at=contract.created_at,
    )


# ---------- Astra Client : factures et déclarations ----------


def list_invoices_for_client(db: Session, account: ClientAccount) -> list[Invoice]:
    access.require(account, ClientPermission.VIEW_INVOICE)
    return list(
        db.scalars(
            select(Invoice)
            .where(Invoice.company_id == account.company_id)
            .order_by(Invoice.issue_date.desc(), Invoice.created_at.desc())
        )
    )


def get_invoice_for_client(db: Session, account: ClientAccount, invoice_id: uuid.UUID) -> Invoice:
    access.require(account, ClientPermission.VIEW_INVOICE)
    invoice = db.scalar(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.company_id == account.company_id)
    )
    if invoice is None:
        raise NotFoundError(INVOICE_NOT_FOUND)
    return invoice


def list_declarations_for_client(db: Session, account: ClientAccount) -> list[PaymentDeclaration]:
    access.require(account, ClientPermission.VIEW_INVOICE)
    return list(
        db.scalars(
            select(PaymentDeclaration)
            .where(PaymentDeclaration.company_id == account.company_id)
            .order_by(PaymentDeclaration.created_at.desc())
        )
    )


def get_declaration_for_client(
    db: Session, account: ClientAccount, declaration_id: uuid.UUID
) -> PaymentDeclaration:
    access.require(account, ClientPermission.VIEW_INVOICE)
    declaration = db.scalar(
        select(PaymentDeclaration).where(
            PaymentDeclaration.id == declaration_id,
            PaymentDeclaration.company_id == account.company_id,
        )
    )
    if declaration is None:
        raise NotFoundError(DECLARATION_NOT_FOUND)
    return declaration


def declare_payment(
    db: Session,
    storage: LocalFileStorage,
    account: ClientAccount,
    invoice: Invoice,
    *,
    amount: Decimal,
    paid_on: date,
    method: PaymentMethod,
    reference: str | None,
    note: str | None,
    proof: tuple[str, BinaryIO] | None,
    max_bytes: int,
) -> PaymentDeclaration:
    """Déclaration d'un paiement externe (§28-29) : jamais confirmée ici."""
    access.require(account, ClientPermission.SUBMIT_PAYMENT_PROOF)
    db.execute(select(Invoice.id).where(Invoice.id == invoice.id).with_for_update())
    db.refresh(invoice)
    if not is_open(invoice):
        raise ConflictError("Cette facture n'attend pas de paiement.")
    if amount <= ZERO:
        raise ServiceError("Le montant doit être positif.")
    if amount > declarable_amount(invoice):
        raise ServiceError(
            "Le montant dépasse le reste à payer (paiements déjà déclarés en attente compris)."
        )
    if paid_on > date.today():
        raise ServiceError("La date du paiement ne peut pas être dans le futur.")
    reference = (reference or "").strip() or None
    if proof is None and reference is None:
        raise ServiceError(
            "Joignez une preuve de paiement ou indiquez la référence de la transaction."
        )
    if reference is not None and len(reference) > 120:
        raise ServiceError("Référence trop longue.")
    if note is not None and len(note) > 2_000:
        raise ServiceError("Commentaire trop long.")

    declaration = PaymentDeclaration(
        invoice_id=invoice.id,
        company_id=account.company_id,
        declared_by_account_id=account.id,
        amount=amount,
        paid_on=paid_on,
        method=method,
        reference=reference,
        note=(note or "").strip() or None,
    )
    stored_key = None
    if proof is not None:
        filename, source = proof
        stored_key = files.attach(
            storage, declaration, filename=filename, source=source, max_bytes=max_bytes
        )
    try:
        db.add(declaration)
        db.flush()
        audit.record(
            db,
            account,
            project_id=invoice.project_id,
            entity_type="payment_declaration",
            entity_id=declaration.id,
            action="declared",
            changes={"invoice": invoice.number, "amount": amount, "method": method},
        )
        notification_service.notify_many(
            db,
            user_ids=conversations.client_managers(db),
            actor=None,
            kind=NotificationKind.PAYMENT_DECLARED,
            title=f"Paiement déclaré · {invoice.number}",
            body=f"{account.company.name} · {format_money(amount, invoice.currency)} · à vérifier",
            entity_type="payment_declaration",
            entity_id=declaration.id,
        )
        db.commit()
    except Exception:
        db.rollback()
        if stored_key:
            storage.delete(stored_key)
        raise
    db.refresh(declaration)
    return declaration


# ---------- Astra Hub : factures ----------


def _company(db: Session, company_id: uuid.UUID) -> ClientCompany:
    company = db.get(ClientCompany, company_id)
    if company is None:
        raise NotFoundError("Entreprise introuvable.")
    return company


def _check_project(db: Session, company_id: uuid.UUID, project_id: uuid.UUID | None) -> None:
    if project_id is None:
        return
    project = db.get(Project, project_id)
    if project is None or project.client_company_id != company_id:
        raise NotFoundError("Projet introuvable pour cette entreprise.")


def list_invoices_for_hub(
    db: Session, user: User, *, company_id: uuid.UUID | None, open_only: bool
) -> list[Invoice]:
    require_client_manager(user)
    statement = select(Invoice)
    if company_id is not None:
        statement = statement.where(Invoice.company_id == company_id)
    invoices = list(db.scalars(statement.order_by(Invoice.issue_date.desc()).limit(500)))
    return [i for i in invoices if is_open(i)] if open_only else invoices


def get_invoice_for_hub(db: Session, user: User, invoice_id: uuid.UUID) -> Invoice:
    require_client_manager(user)
    invoice = db.get(Invoice, invoice_id)
    if invoice is None:
        raise NotFoundError(INVOICE_NOT_FOUND)
    return invoice


def create_invoice(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    *,
    company_id: uuid.UUID,
    title: str,
    amount: Decimal,
    currency: str,
    issue_date: date,
    due_date: date | None,
    project_id: uuid.UUID | None,
    upload: tuple[str, BinaryIO] | None,
    max_bytes: int,
) -> Invoice:
    require_client_manager(user)
    company = _company(db, company_id)
    _check_project(db, company_id, project_id)
    if amount <= ZERO:
        raise ServiceError("Le montant doit être positif.")
    if due_date is not None and due_date < issue_date:
        raise ServiceError("L'échéance précède la date d'émission.")
    invoice = Invoice(
        number=numbering.next_number(db, Invoice.number, "AST"),
        company_id=company.id,
        project_id=project_id,
        title=title.strip(),
        amount=amount,
        currency=currency,
        issue_date=issue_date,
        due_date=due_date,
        created_by_id=user.id,
    )
    stored_key = None
    if upload is not None:
        filename, source = upload
        stored_key = files.attach(
            storage, invoice, filename=filename, source=source, max_bytes=max_bytes
        )
    try:
        db.add(invoice)
        db.flush()
        activity_service.record(
            db,
            actor=user,
            project_id=project_id,
            entity_type="invoice",
            entity_id=invoice.id,
            action="created",
            changes={"number": invoice.number, "amount": amount},
        )
        notifications.notify_company(
            db,
            company.id,
            ClientPermission.VIEW_INVOICE,
            kind=ClientNotificationKind.INVOICE_CREATED,
            title=f"Nouvelle facture {invoice.number}",
            body=f"{invoice.title} · {format_money(amount, currency)}",
            entity_type="invoice",
            entity_id=invoice.id,
        )
        db.commit()
    except Exception:
        db.rollback()
        if stored_key:
            storage.delete(stored_key)
        raise
    return invoice


def update_invoice(db: Session, user: User, invoice: Invoice, data: InvoiceUpdate) -> Invoice:
    require_client_manager(user)
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(invoice, changes)
    for field, value in changes.items():
        setattr(invoice, field, value)
    if delta:
        activity_service.record(
            db,
            actor=user,
            project_id=invoice.project_id,
            entity_type="invoice",
            entity_id=invoice.id,
            action="updated",
            changes=delta,
        )
    db.commit()
    return invoice


def list_declarations_for_hub(
    db: Session,
    user: User,
    *,
    status: PaymentDeclarationStatus | None,
    pending_only: bool,
) -> list[PaymentDeclaration]:
    require_client_manager(user)
    statement = select(PaymentDeclaration)
    if status is not None:
        statement = statement.where(PaymentDeclaration.status == status)
    if pending_only:
        statement = statement.where(PaymentDeclaration.status.in_(PENDING))
    return list(db.scalars(statement.order_by(PaymentDeclaration.created_at.desc()).limit(500)))


def get_declaration_for_hub(
    db: Session, user: User, declaration_id: uuid.UUID
) -> PaymentDeclaration:
    require_client_manager(user)
    declaration = db.get(PaymentDeclaration, declaration_id)
    if declaration is None:
        raise NotFoundError(DECLARATION_NOT_FOUND)
    return declaration


def start_review(db: Session, user: User, declaration: PaymentDeclaration) -> PaymentDeclaration:
    require_client_manager(user)
    if declaration.status != PaymentDeclarationStatus.DECLARED:
        raise ConflictError("Cette déclaration est déjà en cours de vérification ou traitée.")
    declaration.status = PaymentDeclarationStatus.UNDER_REVIEW
    activity_service.record(
        db,
        actor=user,
        project_id=declaration.invoice.project_id,
        entity_type="payment_declaration",
        entity_id=declaration.id,
        action="review_started",
    )
    db.commit()
    return declaration


def review_declaration(
    db: Session, user: User, declaration: PaymentDeclaration, data: DeclarationReview
) -> PaymentDeclaration:
    """Confirme ou refuse un paiement déclaré (§30-31). Le refus est motivé."""
    require_client_manager(user)
    db.execute(
        select(PaymentDeclaration.id)
        .where(PaymentDeclaration.id == declaration.id)
        .with_for_update()
    )
    db.refresh(declaration)
    if declaration.status not in PENDING:
        raise ConflictError("Cette déclaration a déjà été traitée.")
    invoice = declaration.invoice
    if data.confirm:
        confirmed = (
            data.confirmed_amount if data.confirmed_amount is not None else declaration.amount
        )
        declaration.status = PaymentDeclarationStatus.CONFIRMED
        declaration.confirmed_amount = confirmed
        declaration.rejection_reason = None
        kind = ClientNotificationKind.PAYMENT_CONFIRMED
        title = f"Paiement confirmé · {invoice.number}"
        body = f"{format_money(confirmed, invoice.currency)} reçus. Merci !"
    else:
        declaration.status = PaymentDeclarationStatus.REJECTED
        declaration.rejection_reason = (data.rejection_reason or "").strip()
        kind = ClientNotificationKind.PAYMENT_REJECTED
        title = f"Paiement refusé · {invoice.number}"
        body = declaration.rejection_reason
    declaration.reviewed_by_id = user.id
    declaration.reviewed_at = datetime.now(UTC)
    activity_service.record(
        db,
        actor=user,
        project_id=invoice.project_id,
        entity_type="payment_declaration",
        entity_id=declaration.id,
        action="confirmed" if data.confirm else "rejected",
        changes={"invoice": invoice.number, "amount": declaration.confirmed_amount},
    )
    recipients = access.recipients(db, declaration.company_id, ClientPermission.VIEW_INVOICE)
    if declaration.declared_by_account_id:
        recipients.append(declaration.declared_by_account_id)
    notifications.notify_accounts(
        db,
        recipients,
        kind=kind,
        title=title,
        body=body,
        entity_type="invoice",
        entity_id=invoice.id,
    )
    db.commit()
    db.refresh(declaration)
    return declaration


# ---------- Contrats ----------


def list_contracts_for_client(db: Session, account: ClientAccount) -> list[Contract]:
    access.require(account, ClientPermission.VIEW_CONTRACT)
    return list(
        db.scalars(
            select(Contract)
            .where(
                Contract.company_id == account.company_id, Contract.status != ContractStatus.DRAFT
            )
            .order_by(Contract.created_at.desc())
        )
    )


def get_contract_for_client(
    db: Session, account: ClientAccount, contract_id: uuid.UUID
) -> Contract:
    access.require(account, ClientPermission.VIEW_CONTRACT)
    contract = db.scalar(
        select(Contract).where(
            Contract.id == contract_id,
            Contract.company_id == account.company_id,
            Contract.status != ContractStatus.DRAFT,
        )
    )
    if contract is None:
        raise NotFoundError(CONTRACT_NOT_FOUND)
    return contract


def list_contracts_for_hub(
    db: Session, user: User, *, company_id: uuid.UUID | None
) -> list[Contract]:
    require_client_manager(user)
    statement = select(Contract)
    if company_id is not None:
        statement = statement.where(Contract.company_id == company_id)
    return list(db.scalars(statement.order_by(Contract.created_at.desc()).limit(500)))


def get_contract_for_hub(db: Session, user: User, contract_id: uuid.UUID) -> Contract:
    require_client_manager(user)
    contract = db.get(Contract, contract_id)
    if contract is None:
        raise NotFoundError(CONTRACT_NOT_FOUND)
    return contract


def _notify_contract(db: Session, contract: Contract) -> None:
    notifications.notify_company(
        db,
        contract.company_id,
        ClientPermission.VIEW_CONTRACT,
        kind=ClientNotificationKind.CONTRACT_AVAILABLE,
        title=f"Contrat disponible : {contract.title}",
        body=contract.number,
        entity_type="contract",
        entity_id=contract.id,
    )


def create_contract(
    db: Session, user: User, company_id: uuid.UUID, data: ContractCreate
) -> Contract:
    require_client_manager(user)
    _company(db, company_id)
    _check_project(db, company_id, data.project_id)
    if db.scalar(select(Contract.id).where(Contract.number == data.number)):
        raise ConflictError("Ce numéro de contrat existe déjà.")
    contract = Contract(company_id=company_id, created_by_id=user.id, **data.model_dump())
    db.add(contract)
    db.flush()
    activity_service.record(
        db,
        actor=user,
        project_id=data.project_id,
        entity_type="contract",
        entity_id=contract.id,
        action="created",
        changes={"number": contract.number},
    )
    if contract.status != ContractStatus.DRAFT:
        _notify_contract(db, contract)
    db.commit()
    return contract


def update_contract(db: Session, user: User, contract: Contract, data: ContractUpdate) -> Contract:
    require_client_manager(user)
    changes = data.model_dump(exclude_unset=True)
    if "project_id" in changes:
        _check_project(db, contract.company_id, changes["project_id"])
    was_draft = contract.status == ContractStatus.DRAFT
    delta = activity_service.diff(contract, changes)
    for field, value in changes.items():
        setattr(contract, field, value)
    if delta:
        activity_service.record(
            db,
            actor=user,
            project_id=contract.project_id,
            entity_type="contract",
            entity_id=contract.id,
            action="updated",
            changes=delta,
        )
    if was_draft and contract.status != ContractStatus.DRAFT:
        _notify_contract(db, contract)
    db.commit()
    return contract


def set_file(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    entity: Contract | Invoice,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> Contract | Invoice:
    """Remplace le PDF d'une facture ou d'un contrat."""
    require_client_manager(user)
    previous = entity.file_key
    key = files.attach(storage, entity, filename=filename, source=source, max_bytes=max_bytes)
    try:
        db.commit()
    except Exception:
        db.rollback()
        storage.delete(key)
        raise
    if previous:
        storage.delete(previous)
    return entity
