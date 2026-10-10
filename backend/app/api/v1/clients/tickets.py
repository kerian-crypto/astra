import uuid

from fastapi import APIRouter

from app.api.deps import CurrentUser, DbSession
from app.models.client_enums import TicketStatus
from app.schemas.client.ticket import TicketHub, TicketUpdate
from app.services.client import tickets

router = APIRouter(prefix="/clients/tickets", tags=["clients"])


@router.get("", response_model=list[TicketHub])
def list_tickets(
    user: CurrentUser,
    db: DbSession,
    status: TicketStatus | None = None,
    company_id: uuid.UUID | None = None,
    open_only: bool = False,
) -> list[TicketHub]:
    return [
        tickets.to_hub(db, t)
        for t in tickets.list_for_hub(
            db, user, status=status, company_id=company_id, open_only=open_only
        )
    ]


@router.get("/{ticket_id}", response_model=TicketHub)
def read_ticket(ticket_id: uuid.UUID, user: CurrentUser, db: DbSession) -> TicketHub:
    return tickets.to_hub(db, tickets.get_for_hub(db, user, ticket_id))


@router.patch("/{ticket_id}", response_model=TicketHub)
def update_ticket(
    ticket_id: uuid.UUID, body: TicketUpdate, user: CurrentUser, db: DbSession
) -> TicketHub:
    ticket = tickets.get_for_hub(db, user, ticket_id)
    return tickets.to_hub(db, tickets.update(db, user, ticket, body))
