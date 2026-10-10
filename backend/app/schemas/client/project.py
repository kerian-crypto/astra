import uuid
from datetime import date, datetime

from pydantic import BaseModel

from app.models.client_enums import ClientProjectStatus


class TeamMemberView(BaseModel):
    """Membre d'Astra tel que le client le voit : nom et fonction seulement."""

    full_name: str
    job_title: str | None
    is_lead: bool


class ClientProjectSummary(BaseModel):
    id: uuid.UUID
    name: str
    status: ClientProjectStatus
    progress: int
    due_date: date | None
    updated_at: datetime
    pending_validations: int = 0


class ClientProjectView(ClientProjectSummary):
    """Représentation autorisée d'un projet (§15, §46) : ni budget, ni tâches,
    ni notes, ni membres internes au-delà du nom et de la fonction."""

    description: str | None
    summary: str | None
    created_at: datetime
    team: list[TeamMemberView]
    deliverable_count: int
    document_count: int
    conversation_id: uuid.UUID | None


class TimelineEvent(BaseModel):
    """Événement du projet visible du client, au libellé construit côté serveur."""

    id: uuid.UUID
    kind: str
    label: str
    actor_name: str | None
    entity_id: uuid.UUID
    created_at: datetime
