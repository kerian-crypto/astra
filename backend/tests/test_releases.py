"""Mises à jour des applications Android publiées sur le serveur."""

import hashlib
import json

import pytest

from app.core.config import get_settings

APK = b"PK\x03\x04fake-apk"


@pytest.fixture
def releases_dir(tmp_path, client):
    settings = get_settings()
    previous = settings.RELEASES_DIR
    settings.RELEASES_DIR = str(tmp_path)
    folder = tmp_path / "client"
    folder.mkdir()
    (folder / "astra_client-1.0.1+2.apk").write_bytes(APK)
    (folder / "release.json").write_text(
        json.dumps(
            {
                "version": "1.0.1",
                "build_number": 2,
                "min_build_number": 1,
                "notes": "Corrections",
                "file": "astra_client-1.0.1+2.apk",
                "size_bytes": len(APK),
                "sha256": hashlib.sha256(APK).hexdigest(),
            }
        )
    )
    yield tmp_path
    settings.RELEASES_DIR = previous


def test_latest_release_is_public_and_downloadable(client, releases_dir):
    latest = client.get("/api/v1/releases/client/latest")
    download = client.get("/api/v1/releases/client/download")

    assert latest.status_code == 200
    assert latest.json()["build_number"] == 2
    assert latest.json()["download_path"] == "releases/client/download"
    assert "file" not in latest.json()
    assert download.content == APK
    assert download.headers["content-type"] == "application/vnd.android.package-archive"


def test_unknown_app_or_missing_release_is_404(client, releases_dir):
    assert client.get("/api/v1/releases/hub/latest").status_code == 404
    assert client.get("/api/v1/releases/../etc/latest").status_code == 404
    assert client.get("/api/v1/releases/autre/download").status_code == 404


def test_manifest_cannot_point_outside_its_folder(client, releases_dir):
    manifest = releases_dir / "client" / "release.json"
    data = json.loads(manifest.read_text())
    data["file"] = "../hub/secret.apk"
    manifest.write_text(json.dumps(data))

    assert client.get("/api/v1/releases/client/download").status_code == 404
