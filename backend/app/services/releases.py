"""Mises à jour des applications Android distribuées hors Play Store.

Chaque application a un dossier dans `RELEASES_DIR` (publié par
`infra/aws/publish-release.sh`) :

    <RELEASES_DIR>/<app>/release.json   version, numéro de build, notes…
    <RELEASES_DIR>/<app>/<fichier>.apk

L'app compare son numéro de build à celui publié et propose la mise à jour.
"""

import json
from pathlib import Path

from pydantic import BaseModel, Field, ValidationError

from app.services.errors import NotFoundError

# Nom public de l'application → dossier sur le serveur.
APPS = {"hub": "hub", "client": "client"}
NO_RELEASE = "Aucune version publiée pour cette application."


class ReleaseManifest(BaseModel):
    version: str = Field(min_length=1, max_length=40)
    build_number: int = Field(ge=1)
    # En dessous de ce build, la mise à jour est obligatoire.
    min_build_number: int = Field(default=1, ge=1)
    notes: str | None = Field(default=None, max_length=4_000)
    file: str = Field(pattern=r"^[A-Za-z0-9._+-]+\.apk$")
    size_bytes: int = Field(ge=1)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


def _folder(releases_dir: str, app: str) -> Path:
    if app not in APPS:
        raise NotFoundError("Application inconnue.")
    return Path(releases_dir) / APPS[app]


def latest(releases_dir: str, app: str) -> ReleaseManifest:
    manifest = _folder(releases_dir, app) / "release.json"
    try:
        return ReleaseManifest.model_validate(json.loads(manifest.read_text(encoding="utf-8")))
    except (OSError, ValueError, ValidationError):
        raise NotFoundError(NO_RELEASE) from None


def apk_path(releases_dir: str, app: str) -> tuple[ReleaseManifest, Path]:
    release = latest(releases_dir, app)
    # `file` est validé (pas de « / ») : le chemin reste dans le dossier de l'app.
    path = _folder(releases_dir, app) / release.file
    if not path.is_file():
        raise NotFoundError(NO_RELEASE)
    return release, path
