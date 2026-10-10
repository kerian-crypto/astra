"""Demandes de support (§34-35, §63). Chaque ticket a sa conversation."""

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    ClientAccount,
    ClientCompany,
    ClientConversation,
    Project,
    SupportTicket,
    User,
)
from app.models.client_enums import (
    ClientNotificationKind,
    ClientPermission,
    ConversationKind,
    TicketStatus,
)
from app.models.enums import NotificationKind
from app.schemas.client.ticket import TicketCreate, TicketHub, TicketUpdate, TicketView
from app.services import activity_service, notification_service
from app.services.client import access, audit, conversations, notifications, numbering
from app.services.client.hub_access import can_manage_clients
from app.services.client.labels import TICKET_STATUS_LABELS
from app.services.errors import NotFoundError, PermissionDeniedError

TICKET_NOT_FOUND = "Ticket introuvable."
OPEN_STATUSES = frozenset(
    {
        TicketStatus.NEW,
        TicketStatus.ACKNOWLEDGED,
        TicketStatus.IN_PROGRESS,
        TicketStatus.WAITING_CLIENT,
    }
)


def _conversation(db: Session, ticket: SupportTicket) -> ClientConversation | None:
    return db.scalar(select(ClientConversation).where(ClientConversation.ticket_id == ticket.id))


def to_view(db: Session, ticket: SupportTicket) -> TicketView:
    project = db.get(Project, ticket.project_id) if ticket.project_id else None
    conversation = _conversation(db, ticket)
    return TicketView(
        id=ticket.id,
        number=ticket.number,
        type=ticket.type,
        subject=ticket.subject,
        description=ticket.description,
        status=ticket.status,
        priority=ticket.priority,
        project_id=ticket.project_id,
        project_name=project.name if project else None,
        created_by_name=ticket.created_by.full_name if ticket.created_by else None,
        conversation_id=conversation.id if conversation else None,
        created_at=ticket.created_at,
        updated_at=ticket.updated_at,
    )


def to_hub(db: Session, ticket: SupportTicket) -> TicketHub:
    company = db.get(ClientCompany, ticket.company_id)
    return TicketHub(
        **to_view(db, ticket).model_dump(),
        company_id=ticket.company_id,
        company_name=company.name,
        assignee_id=ticket.assignee_id,
        assignee_name=ticket.assignee.full_name if ticket.assignee else None,
    )


# ---------- Astra Client ----------


def list_for_client(
    db: Session, account: ClientAccount, *, open_only: bool = False
) -> list[SupportTicket]:
    access.require(account, ClientPermission.CREATE_TICKET)
    statement = select(SupportTicket).where(SupportTicket.company_id == account.company_id)
    if open_only:
        statement = statement.where(SupportTicket.status.in_(OPEN_STATUSES))
    return list(db.scalars(statement.order_by(SupportTicket.updated_at.desc())))


def get_for_client(db: Session, account: ClientAccount, ticket_id: uuid.UUID) -> SupportTicket:
    access.require(account, ClientPermission.CREATE_TICKET)
    ticket = db.scalar(
        select(SupportTicket).where(
            SupportTicket.id == ticket_id, SupportTicket.company_id == account.company_id
        )
    )
    if ticket is None:
        raise NotFoundError(TICKET_NOT_FOUND)
    return ticket


def create(db: Session, account: ClientAccount, data: TicketCreate) -> SupportTicket:
    access.require(account, ClientPermission.CREATE_TICKET)
    if data.project_id is not None:
        access.get_project(db, account, data.project_id)
    ticket = SupportTicket(
        number=numbering.next_number(db, SupportTicket.number, "SUP"),
        company_id=account.company_id,
        project_id=data.project_id,
        created_by_account_id=account.id,
        type=data.type,
        subject=data.subject.strip(),
        description=data.description.strip(),
        priority=data.priority,
    )
    db.add(ticket)
    db.flush()
    db.add(
        ClientConversation(
            company_id=account.company_id,
            kind=ConversationKind.TICKET,
            subject=f"{ticket.number} · {ticket.subject}",
            project_id=data.project_id,
            ticket_id=ticket.id,
        )
    )
    audit.record(
        db,
        account,
        project_id=data.project_id,
        entity_type="support_ticket",
        entity_id=ticket.id,
        action="created",
        changes={"number": ticket.number, "subject": ticket.subject},
    )
    notification_service.notify_many(
        db,
        user_ids=conversations.client_managers(db),
        actor=None,
        kind=NotificationKind.CLIENT_TICKET,
        title=f"Nouveau ticket {ticket.number} · {account.company.name}",
        body=ticket.subject,
        entity_type="support_ticket",
        entity_id=ticket.id,
    )
    db.commit()
    return ticket


# ---------- Astra Hub ----------


def _hub_statement(user: User):
    statement = select(SupportTicket)
    if can_manage_clients(user):
        return statement
    return statement.where(SupportTicket.assignee_id == user.id)


def list_for_hub(
    db: Session,
    user: User,
    *,
    status: TicketStatus | None,
    company_id: uuid.UUID | None,
    open_only: bool,
) -> list[SupportTicket]:
    statement = _hub_statement(user)
    if status is not None:
        statement = statement.where(SupportTicket.status == status)
    if open_only:
        statement = statement.where(SupportTicket.status.in_(OPEN_STATUSES))
    if company_id is not None:
        statement = statement.where(SupportTicket.company_id == company_id)
    return list(db.scalars(statement.order_by(SupportTicket.updated_at.desc()).limit(200)))


def get_for_hub(db: Session, user: User, ticket_id: uuid.UUID) -> SupportTicket:
    ticket = db.scalar(_hub_statement(user).where(SupportTicket.id == ticket_id))
    if ticket is None:
        raise NotFoundError(TICKET_NOT_FOUND)
    return ticket


def update(db: Session, user: User, ticket: SupportTicket, data: TicketUpdate) -> SupportTicket:
    changes = data.model_dump(exclude_unset=True)
    if "assignee_id" in changes:
        if not can_manage_clients(user):
            raise PermissionDeniedError(
                "Seuls les managers et administrateurs assignent un ticket."
            )
        assignee_id = changes["assignee_id"]
        if assignee_id is not None:
            assignee = db.get(User, assignee_id)
            if assignee is None or not assignee.is_active:
                raise NotFoundError("Membre introuvable.")
    delta = activity_service.diff(ticket, changes)
    for field, value in changes.items():
        setattr(ticket, field, value)
    if not delta:
        return ticket
    activity_service.record(
        db,
        actor=user,
        project_id=ticket.project_id,
        entity_type="support_ticket",
        entity_id=ticket.id,
        action="updated",
        changes=delta,
    )
    if "assignee_id" in delta and ticket.assignee_id:
        notification_service.notify(
            db,
            user_id=ticket.assignee_id,
            actor=user,
            kind=NotificationKind.CLIENT_TICKET,
            title=f"Ticket {ticket.number} vous est assigné",
            body=ticket.subject,
            entity_type="support_ticket",
            entity_id=ticket.id,
        )
    if "status" in delta:
        recipients = access.recipients(db, ticket.company_id, ClientPermission.CREATE_TICKET)
        notifications.notify_accounts(
            db,
            recipients,
            kind=ClientNotificationKind.TICKET_UPDATED,
            title=f"Ticket {ticket.number} : {TICKET_STATUS_LABELS[ticket.status]}",
            body=ticket.subject,
            entity_type="support_ticket",
            entity_id=ticket.id,
        )
    db.commit()
    db.refresh(ticket)
    return ticket
