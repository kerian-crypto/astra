import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.models.client_enums import BriefStatus
from app.schemas.client.common import AttachedFile
from app.schemas.plan import ProjectPlan


class ChoiceView(BaseModel):
    value: str
    label: str
    description: str | None = None


class QuestionView(BaseModel):
    id: str
    label: str
    type: str
    required: bool
    help: str | None = None
    example: str | None = None
    choices: list[ChoiceView] = []
    min_items: int | None = None
    max_items: int | None = None
    allow_other: bool = False


class SectionView(BaseModel):
    id: str
    title: str
    intro: str
    questions: list[QuestionView]


class QuestionnaireView(BaseModel):
    sections: list[SectionView]


class BriefFileView(BaseModel):
    id: uuid.UUID
    question_id: str
    file: AttachedFile


class SectionProgress(BaseModel):
    section_id: str
    answered: int
    total: int


class BriefView(BaseModel):
    id: uuid.UUID
    status: BriefStatus
    title: str
    answers: dict[str, Any]
    current_section: str | None
    progress: list[SectionProgress]
    missing_required: list[str]
    files: list[BriefFileView]
    submitted_at: datetime | None
    project_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


class BriefHub(BriefView):
    company_id: uuid.UUID
    company_name: str
    company_self_registered: bool
    author_name: str | None
    proposed_plan: ProjectPlan


class BriefSave(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answers: dict[str, Any] = Field(default_factory=dict, max_length=100)
    current_section: str | None = Field(default=None, max_length=40)


class BriefConvert(BaseModel):
    """Plan retouché par le membre ; absent = plan proposé tel quel."""

    model_config = ConfigDict(extra="forbid")

    plan: ProjectPlan | None = None
