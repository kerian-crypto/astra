"""Entrées et sorties d'ASTRA AI.

Les classes `...Draft` décrivent ce que le modèle doit produire (schéma JSON
imposé à Ronda) ; les classes `...Proposal` sont ce que reçoit l'humain, qui
valide avant toute création (« l'IA propose, l'humain décide »).
"""

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.models.enums import (
    AIActionKind,
    AIActionStatus,
    AIFocusType,
    AIMessageStatus,
    AIRole,
    Priority,
)
from app.schemas.plan import ProjectPlan
from app.schemas.search import SearchType


class ChatTurn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str = Field(max_length=8_000)


class AskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question: str = Field(min_length=1, max_length=2_000)
    history: list[ChatTurn] = Field(default=[], max_length=10)


class Source(BaseModel):
    number: int
    type: SearchType | Literal["work", "project", "channel"]
    id: uuid.UUID | None
    title: str


class AskResponse(BaseModel):
    answer: str
    sources: list[Source]


class AIStatus(BaseModel):
    enabled: bool
    reachable: bool
    model: str | None


# ---------- Planification (§13) ----------


class PlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    idea: str = Field(min_length=10, max_length=4_000)


# Les brouillons n'ont volontairement aucune borne de longueur : llama.cpp
# traduit maxLength/maxItems en grammaires très coûteuses (génération ~6x
# plus lente mesurée sur CPU). Les limites sont appliquées après coup par
# `app.ai.service` (troncature) et demandées dans la consigne.


class DraftTask(BaseModel):
    title: str
    description: str
    priority: Priority


class DraftPhase(BaseModel):
    name: str
    description: str
    tasks: list[DraftTask]


class PlanDraft(BaseModel):
    name: str
    objective: str
    description: str
    phases: list[DraftPhase]
    deliverables: list[str]
    risks: list[str]
    required_skills: list[str]
    estimated_workload_days: int


class PlanProposal(BaseModel):
    plan: ProjectPlan
    deliverables: list[str]
    risks: list[str]
    required_skills: list[str]
    estimated_workload_days: int


# ---------- Réunions (§15) ----------


class DraftDecision(BaseModel):
    title: str
    description: str


class DraftMeetingTask(BaseModel):
    title: str
    description: str
    assignee_number: int | None  # numéro du participant dans la liste fournie
    due_date: str | None  # AAAA-MM-JJ


class MeetingSummaryDraft(BaseModel):
    summary: str
    decisions: list[DraftDecision]
    open_questions: list[str]
    tasks: list[DraftMeetingTask]
    risks: list[str]


class ProposedMeetingTask(BaseModel):
    title: str
    description: str
    assignee_id: uuid.UUID | None
    assignee_name: str | None
    due_date: str | None


class MeetingSummaryProposal(BaseModel):
    summary: str
    decisions: list[DraftDecision]
    open_questions: list[str]
    tasks: list[ProposedMeetingTask]
    risks: list[str]


class HealthReport(BaseModel):
    report: str


# ---------- Historique des conversations ----------


class AIFocus(BaseModel):
    """Écran consulté : Ronda le lit, dans la limite des droits du membre."""

    model_config = ConfigDict(extra="forbid")

    type: AIFocusType
    id: uuid.UUID


class ConversationQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2_000)
    ]
    focus: AIFocus | None = None
    # Fuseau de l'appareil : « lundi 14h » se lit à l'heure locale du membre.
    utc_offset_minutes: int = Field(default=0, ge=-14 * 60, le=14 * 60)


class DraftAction(BaseModel):
    """Action éventuelle demandée par le membre, telle que Ronda la comprend."""

    kind: Literal["none", "create_project", "schedule_meeting", "create_task", "create_decision"]
    title: str
    description: str
    project_number: int | None  # numéro [n] d'un élément du contexte
    date: str | None  # AAAA-MM-JJ : échéance, ou jour de la réunion
    time: str | None  # HH:MM, heure locale de la réunion
    duration_minutes: int | None
    priority: Priority | None


class DraftReply(BaseModel):
    answer: str
    action: DraftAction


class ProposedAction(BaseModel):
    """Action en attente de validation, enregistrée avec la réponse de Ronda."""

    kind: AIActionKind
    status: AIActionStatus
    title: str
    details: list[str]
    payload: dict
    result_type: str | None = None
    result_id: uuid.UUID | None = None


class ActionDecision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    apply: bool


class AIMessagePublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    role: AIRole
    content: str
    sources: list[Source]
    status: AIMessageStatus
    focus_type: AIFocusType | None
    focus_id: uuid.UUID | None
    focus_title: str | None
    action: ProposedAction | None
    created_at: datetime


class AIConversationSummary(BaseModel):
    id: uuid.UUID
    title: str
    created_at: datetime
    updated_at: datetime
    is_pending: bool  # Ronda génère encore une réponse


class AIConversationDetail(AIConversationSummary):
    messages: list[AIMessagePublic]
