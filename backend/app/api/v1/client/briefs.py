"""Questionnaire de cadrage (cahier des charges) côté Astra Client."""

import uuid
from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status
from fastapi.responses import FileResponse

from app.api.deps import AppSettings, ClientUploadQuota, CurrentClient, DbSession, Storage
from app.api.files import attached_file_response
from app.schemas.client.brief import BriefSave, BriefView, QuestionnaireView
from app.services.client import brief_views, briefs

router = APIRouter(prefix="/briefs", tags=["client-briefs"])


@router.get("/questionnaire", response_model=QuestionnaireView)
def questionnaire() -> QuestionnaireView:
    return brief_views.questionnaire()


@router.get("", response_model=list[BriefView])
def list_briefs(account: CurrentClient, db: DbSession) -> list[BriefView]:
    return [brief_views.to_view(b) for b in briefs.list_for_client(db, account)]


@router.post("", response_model=BriefView, status_code=status.HTTP_201_CREATED)
def start_brief(account: CurrentClient, db: DbSession) -> BriefView:
    """Nouveau cahier des charges (ou reprise du brouillon en cours)."""
    return brief_views.to_view(briefs.start(db, account))


@router.get("/{brief_id}", response_model=BriefView)
def read_brief(brief_id: uuid.UUID, account: CurrentClient, db: DbSession) -> BriefView:
    return brief_views.to_view(briefs.get_for_client(db, account, brief_id))


@router.patch("/{brief_id}", response_model=BriefView)
def save_brief(
    brief_id: uuid.UUID, body: BriefSave, account: CurrentClient, db: DbSession
) -> BriefView:
    brief = briefs.get_for_client(db, account, brief_id)
    return brief_views.to_view(
        briefs.save(db, account, brief, answers=body.answers, current_section=body.current_section)
    )


@router.post(
    "/{brief_id}/files",
    response_model=BriefView,
    status_code=status.HTTP_201_CREATED,
    dependencies=[ClientUploadQuota],
)
def add_file(
    brief_id: uuid.UUID,
    question_id: Annotated[str, Form(max_length=40)],
    file: Annotated[UploadFile, File()],
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
    settings: AppSettings,
) -> BriefView:
    brief = briefs.get_for_client(db, account, brief_id)
    briefs.add_file(
        db,
        storage,
        brief,
        question_id=question_id,
        filename=file.filename or "reference",
        source=file.file,
        max_bytes=settings.MAX_CLIENT_UPLOAD_BYTES,
    )
    return brief_views.to_view(brief)


@router.delete("/{brief_id}/files/{file_id}", response_model=BriefView)
def remove_file(
    brief_id: uuid.UUID,
    file_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
) -> BriefView:
    brief = briefs.get_for_client(db, account, brief_id)
    briefs.remove_file(db, storage, brief, file_id)
    return brief_views.to_view(brief)


@router.get("/{brief_id}/files/{file_id}", response_class=FileResponse)
def download_file(
    brief_id: uuid.UUID,
    file_id: uuid.UUID,
    account: CurrentClient,
    db: DbSession,
    storage: Storage,
) -> FileResponse:
    brief = briefs.get_for_client(db, account, brief_id)
    return attached_file_response(storage, briefs.get_file(brief, file_id))


@router.post("/{brief_id}/submit", response_model=BriefView)
def submit_brief(brief_id: uuid.UUID, account: CurrentClient, db: DbSession) -> BriefView:
    brief = briefs.get_for_client(db, account, brief_id)
    return brief_views.to_view(briefs.submit(db, account, brief))
