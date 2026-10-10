import uuid

from fastapi import APIRouter, status

from app.api.deps import CurrentClient, DbSession
from app.schemas.client.ticket import TicketCreate, TicketView
from app.services.client import tickets

router = APIRouter(prefix="/tickets", tags=["client-support"])


@router.get("", response_model=list[TicketView])
def list_tickets(
    account: CurrentClient, db: DbSession, open_only: bool = False
) -> list[TicketView]:
    return [
        tickets.to_view(db, t) for t in tickets.list_for_client(db, account, open_only=open_only)
    ]


@router.post("", response_model=TicketView, status_code=status.HTTP_201_CREATED)
def create_ticket(body: TicketCreate, account: CurrentClient, db: DbSession) -> TicketView:
    return tickets.to_view(db, tickets.create(db, account, body))


@router.get("/{ticket_id}", response_model=TicketView)
def read_ticket(ticket_id: uuid.UUID, account: CurrentClient, db: DbSession) -> TicketView:
    return tickets.to_view(db, tickets.get_for_client(db, account, ticket_id))
