"""Accueil d'Astra Client (§13) : synthèse légère et « ce que je dois faire
maintenant ». Chaque bloc respecte les permissions du compte."""

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ClientAccount, Deliverable, Project, ProjectBrief
from app.models.client_enums import (
    ClientPermission,
    DeliverableStatus,
    InvoicePaymentStatus,
    TicketStatus,
)
from app.schemas.client.company import CompanyView
from app.schemas.client.dashboard import ActionItem, DashboardView, Deadline
from app.services.client import (
    access,
    billing,
    conversations,
    documents,
    notifications,
    projects,
    tickets,
)
from app.services.client.labels import format_money

RECENT_DOCUMENTS = 5
NEW_DOCUMENT_DAYS = 7
DEADLINE_HORIZON_DAYS = 60
MAX_DEADLINES = 6


def company_view(account: ClientAccount) -> CompanyView:
    view = CompanyView.model_validate(account.company)
    view.has_logo = account.company.logo_key is not None
    return view


def build(db: Session, account: ClientAccount) -> DashboardView:
    actions: list[ActionItem] = []
    deadlines: list[Deadline] = []
    horizon = date.today() + timedelta(days=DEADLINE_HORIZON_DAYS)
    active = completed = pending_validations = 0

    if account.has_permission(ClientPermission.VIEW_PROJECT):
        company_projects = list(db.scalars(access.company_projects_statement(account)))
        for project in company_projects:
            finished = projects.client_status(project) in projects.FINISHED_STATUSES
            completed += finished
            active += not finished
            if not finished and project.due_date and project.due_date <= horizon:
                deadlines.append(
                    Deadline(
                        kind="project",
                        title=project.name,
                        due_date=project.due_date,
                        entity_type="project",
                        entity_id=project.id,
                    )
                )
        names = {p.id: p.name for p in company_projects}
        for deliverable in db.scalars(access.visible_deliverables_statement(account)):
            if deliverable.status == DeliverableStatus.AWAITING_VALIDATION:
                pending_validations += 1
                actions.append(
                    ActionItem(
                        kind="validation_required",
                        title=deliverable.title,
                        subtitle=names.get(deliverable.project_id),
                        entity_type="deliverable",
                        entity_id=deliverable.id,
                        created_at=deliverable.updated_at,
                    )
                )
            if (
                deliverable.due_date
                and deliverable.status
                in (DeliverableStatus.AWAITING_VALIDATION, DeliverableStatus.CHANGES_REQUESTED)
                and deliverable.due_date <= horizon
            ):
                deadlines.append(
                    Deadline(
                        kind="deliverable",
                        title=deliverable.title,
                        due_date=deliverable.due_date,
                        entity_type="deliverable",
                        entity_id=deliverable.id,
                    )
                )
        _add_upcoming_drafts(db, account, deadlines, horizon)

    pending_invoices = None
    if account.has_permission(ClientPermission.VIEW_INVOICE):
        pending_invoices = 0
        for invoice in billing.list_invoices_for_client(db, account):
            if not billing.is_open(invoice):
                continue
            pending_invoices += 1
            status = billing.payment_status(invoice)
            if status in (
                InvoicePaymentStatus.UNPAID,
                InvoicePaymentStatus.REJECTED,
                InvoicePaymentStatus.PARTIALLY_CONFIRMED,
            ):
                actions.append(
                    ActionItem(
                        kind="payment_rejected"
                        if status == InvoicePaymentStatus.REJECTED
                        else "payment_due",
                        title=f"Facture {invoice.number}",
                        subtitle=format_money(billing.remaining_amount(invoice), invoice.currency),
                        entity_type="invoice",
                        entity_id=invoice.id,
                        created_at=None,
                    )
                )
            if invoice.due_date and invoice.due_date <= horizon:
                deadlines.append(
                    Deadline(
                        kind="invoice",
                        title=f"Facture {invoice.number}",
                        due_date=invoice.due_date,
                        entity_type="invoice",
                        entity_id=invoice.id,
                    )
                )

    open_tickets = None
    if account.has_permission(ClientPermission.CREATE_TICKET):
        open_list = tickets.list_for_client(db, account, open_only=True)
        open_tickets = len(open_list)
        actions += [
            ActionItem(
                kind="ticket_reply",
                title=f"Ticket {t.number}",
                subtitle=t.subject,
                entity_type="support_ticket",
                entity_id=t.id,
                created_at=t.updated_at,
            )
            for t in open_list
            if t.status == TicketStatus.WAITING_CLIENT
        ]

    recent = []
    if account.has_permission(ClientPermission.VIEW_DOCUMENT):
        recent = documents.list_documents(db, account, limit=RECENT_DOCUMENTS)
        cutoff = date.today() - timedelta(days=NEW_DOCUMENT_DAYS)
        actions += [
            ActionItem(
                kind="new_document",
                title=d.title,
                subtitle=d.project_name,
                entity_type="document",
                entity_id=d.id,
                created_at=d.created_at,
            )
            for d in recent
            if d.created_at.date() >= cutoff and d.category.value not in ("invoice", "deliverable")
        ]

    brief = None
    needs_onboarding = False
    if account.has_permission(ClientPermission.SUBMIT_BRIEF):
        brief = db.scalar(
            select(ProjectBrief)
            .where(ProjectBrief.company_id == account.company_id)
            .order_by(ProjectBrief.created_at.desc())
            .limit(1)
        )
        has_projects = db.scalar(access.company_project_ids(account).limit(1)) is not None
        needs_onboarding = not has_projects and (brief is None or brief.status == "draft")
        if brief is not None and brief.status == "draft":
            actions.insert(
                0,
                ActionItem(
                    kind="brief_draft",
                    title="Terminer votre cahier des charges",
                    subtitle="Reprenez le questionnaire là où vous l'avez laissé",
                    entity_type="project_brief",
                    entity_id=brief.id,
                    created_at=brief.updated_at,
                ),
            )

    deadlines.sort(key=lambda d: d.due_date)
    return DashboardView(
        brief_id=brief.id if brief else None,
        brief_status=brief.status.value if brief else None,
        needs_onboarding=needs_onboarding,
        company=company_view(account),
        active_projects=active,
        completed_projects=completed,
        pending_validations=pending_validations,
        unread_messages=conversations.total_unread_for_client(db, account),
        unread_notifications=notifications.unread_count(db, account),
        pending_invoices=pending_invoices,
        open_tickets=open_tickets,
        actions=actions,
        deadlines=deadlines[:MAX_DEADLINES],
        recent_documents=recent,
    )


def _add_upcoming_drafts(
    db: Session, account: ClientAccount, deadlines: list[Deadline], horizon: date
) -> None:
    """Livraisons prévues (livrables pas encore publiés mais datés)."""
    drafts = db.scalars(
        select(Deliverable).where(
            Deliverable.project_id.in_(
                select(Project.id).where(Project.client_company_id == account.company_id)
            ),
            Deliverable.status == DeliverableStatus.DRAFT,
            Deliverable.due_date.is_not(None),
            Deliverable.due_date <= horizon,
        )
    )
    deadlines += [
        Deadline(
            kind="delivery",
            title=d.title,
            due_date=d.due_date,
            entity_type="project",
            entity_id=d.project_id,
        )
        for d in drafts
    ]
