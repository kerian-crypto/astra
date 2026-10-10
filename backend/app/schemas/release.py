from pydantic import BaseModel


class AppRelease(BaseModel):
    app: str
    version: str
    build_number: int
    min_build_number: int
    notes: str | None
    size_bytes: int
    sha256: str
    # Chemin relatif à l'API (ex. « releases/client/download »).
    download_path: str
