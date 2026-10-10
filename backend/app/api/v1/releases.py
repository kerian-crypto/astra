"""Mises à jour des applications (publiques : l'écran de connexion doit
pouvoir proposer une nouvelle version avant toute session)."""

from fastapi import APIRouter
from fastapi.responses import FileResponse

from app.api.deps import AppSettings
from app.schemas.release import AppRelease
from app.services import releases

router = APIRouter(prefix="/releases", tags=["releases"])


@router.get("/{app}/latest", response_model=AppRelease)
def latest_release(app: str, settings: AppSettings) -> AppRelease:
    release = releases.latest(settings.RELEASES_DIR, app)
    return AppRelease(
        app=app,
        **release.model_dump(exclude={"file"}),
        download_path=f"releases/{app}/download",
    )


@router.get("/{app}/download", response_class=FileResponse)
def download_release(app: str, settings: AppSettings) -> FileResponse:
    release, path = releases.apk_path(settings.RELEASES_DIR, app)
    return FileResponse(
        path,
        media_type="application/vnd.android.package-archive",
        filename=release.file,
        headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "public, max-age=300"},
    )
