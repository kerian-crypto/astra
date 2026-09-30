import uuid
from enum import StrEnum

from pydantic import BaseModel


class SearchType(StrEnum):
    PROJECT = "project"
    TASK = "task"
    DECISION = "decision"
    MEETING = "meeting"
    DOCUMENT = "document"
    MESSAGE = "message"


class SearchHit(BaseModel):
    type: SearchType
    id: uuid.UUID
    title: str
    snippet: str
    # Projet de rattachement ou, pour un message, son canal : pour la navigation.
    project_id: uuid.UUID | None = None
    parent_id: uuid.UUID | None = None
    score: float
