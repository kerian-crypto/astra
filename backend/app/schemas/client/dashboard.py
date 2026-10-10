import uuid
from datetime import date, datetime

from pydantic import BaseModel

from app.schemas.client.company import CompanyView
from app.schemas.client.document import ClientDocumentView


class ActionItem(BaseModel):
    """« Ce que je dois faire maintenant » (§13.1)."""

    kind: str  # validation_required, payment_due, payment_rejected, ticket_reply, new_document
    title: str
    subtitle: str | None
    entity_type: str
    entity_id: uuid.UUID
    created_at: datetime | None


class Deadline(BaseModel):
    kind: str  # project, deliverable, invoice
    title: str
    due_date: date
    entity_type: str
    entity_id: uuid.UUID


class DashboardView(BaseModel):
    company: CompanyView
    active_projects: int
    completed_projects: int
    pending_validations: int
    unread_messages: int
    unread_notifications: int
    pending_invoices: int | None  # nul sans accès aux factures
    open_tickets: int | None  # nul sans accès au support
    actions: list[ActionItem]
    deadlines: list[Deadline]
    recent_documents: list[ClientDocumentView]
    # Questionnaire de cadrage : dernier cahier des charges et besoin de le remplir.
    brief_id: uuid.UUID | None = None
    brief_status: str | None = None
    needs_onboarding: bool = False
