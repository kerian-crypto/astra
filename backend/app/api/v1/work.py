from datetime import date

from fastapi import APIRouter

from app.api.deps import CurrentUser, DbSession
from app.schemas.work import Dashboard, MyWork
from app.services import work_service

router = APIRouter(tags=["work"])


@router.get("/me/work", response_model=MyWork)
def my_work(user: CurrentUser, db: DbSession, today: date | None = None) -> MyWork:
    """`today` permet au client d'utiliser sa date locale (fuseau horaire)."""
    return work_service.my_work(db, user, today or date.today())


@router.get("/dashboard", response_model=Dashboard)
def dashboard(user: CurrentUser, db: DbSession, today: date | None = None) -> Dashboard:
    return work_service.dashboard(db, user, today or date.today())
