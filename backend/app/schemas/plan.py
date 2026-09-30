"""Plan de projet structuré : produit par un humain (décision → projet) ou
proposé par l'IA, puis validé par un humain avant création (spec §13)."""

import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import Priority


class PlannedTask(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5_000)
    priority: Priority = Priority.MEDIUM
    due_date: date | None = None
    assignee_id: uuid.UUID | None = None


class PlannedPhase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=5_000)
    due_date: date | None = None
    tasks: list[PlannedTask] = Field(default=[], max_length=100)


class ProjectPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=10_000)
    objective: str | None = Field(default=None, max_length=10_000)
    priority: Priority = Priority.MEDIUM
    due_date: date | None = None
    budget: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    lead_id: uuid.UUID | None = None
    member_ids: list[uuid.UUID] = Field(default=[], max_length=100)
    phases: list[PlannedPhase] = Field(default=[], max_length=30)
