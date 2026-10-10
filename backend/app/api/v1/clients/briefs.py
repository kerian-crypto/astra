"""Cahiers des charges reçus des clients (Astra Hub)."""

import uuid

from fastapi import APIRouter
from fastapi.responses import FileResponse

from app.api.deps import CurrentUser, DbSession, Storage
from app.api.files import attached_file_response
from app.models.client_enums import BriefStatus
from app.schemas.client.brief import BriefConvert, BriefHub, QuestionnaireView
from app.services.client import brief_views, briefs

router = APIRouter(prefix="/clients/briefs", tags=["clients"])


@router.get("/questionnaire", response_model=QuestionnaireView)
def questionnaire(user: CurrentUser) -> QuestionnaireView:
    return brief_views.questionnaire()


@router.get("", response_model=list[BriefHub])
def list_briefs(
    user: CurrentUser, db: DbSession, status: BriefStatus | None = None
) -> list[BriefHub]:
    return [brief_views.to_hub(db, b) for b in briefs.list_for_hub(db, user, status=status)]


@router.get("/{brief_id}", response_model=BriefHub)
def read_brief(brief_id: uuid.UUID, user: CurrentUser, db: DbSession) -> BriefHub:
    return brief_views.to_hub(db, briefs.get_for_hub(db, user, brief_id))


@router.post("/{brief_id}/start-review", response_model=BriefHub)
def start_review(brief_id: uuid.UUID, user: CurrentUser, db: DbSession) -> BriefHub:
    brief = briefs.get_for_hub(db, user, brief_id)
    return brief_views.to_hub(db, briefs.start_review(db, user, brief))


@router.post("/{brief_id}/convert", response_model=BriefHub)
def convert(brief_id: uuid.UUID, body: BriefConvert, user: CurrentUser, db: DbSession) -> BriefHub:
    """Crée le projet (phases et tâches déduites du questionnaire) et l'ouvre au client."""
    brief = briefs.get_for_hub(db, user, brief_id)
    return brief_views.to_hub(db, briefs.convert(db, user, brief, plan=body.plan))


@router.post("/{brief_id}/archive", response_model=BriefHub)
def archive(brief_id: uuid.UUID, user: CurrentUser, db: DbSession) -> BriefHub:
    brief = briefs.get_for_hub(db, user, brief_id)
    return brief_views.to_hub(db, briefs.archive(db, user, brief))


@router.get("/{brief_id}/files/{file_id}", response_class=FileResponse)
def download_file(
    brief_id: uuid.UUID, file_id: uuid.UUID, user: CurrentUser, db: DbSession, storage: Storage
) -> FileResponse:
    brief = briefs.get_for_hub(db, user, brief_id)
    return attached_file_response(storage, briefs.get_file(brief, file_id))
