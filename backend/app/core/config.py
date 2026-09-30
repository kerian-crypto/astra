from functools import lru_cache
from typing import Annotated

from pydantic import Field, PostgresDsn, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

MIN_SECRET_KEY_LENGTH = 32


class Settings(BaseSettings):
    """Configuration lue depuis l'environnement (ou un fichier .env).

    Aucun secret n'a de valeur par défaut : l'application refuse de démarrer
    si SECRET_KEY ou DATABASE_URL sont absents.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    PROJECT_NAME: str = "ASTRA HUB"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    DATABASE_URL: PostgresDsn

    SECRET_KEY: str = Field(min_length=MIN_SECRET_KEY_LENGTH)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=15, gt=0)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=30, gt=0)

    LOGIN_RATE_LIMIT_ATTEMPTS: int = Field(default=5, gt=0)
    LOGIN_RATE_LIMIT_WINDOW_SECONDS: int = Field(default=300, gt=0)

    # Documents : stockage local (volume Docker en production).
    UPLOAD_DIR: str = "/data/uploads"
    MAX_UPLOAD_BYTES: int = Field(default=20 * 1024 * 1024, gt=0)
    MAX_PHOTO_BYTES: int = Field(default=5 * 1024 * 1024, gt=0)
    # Pièces jointes du chat (photos, vidéos, messages vocaux, documents).
    MAX_CHAT_UPLOAD_BYTES: int = Field(default=50 * 1024 * 1024, gt=0)
    # Envois de fichiers par membre (pièces jointes, photos, documents) :
    # empêche un compte de remplir le disque du serveur.
    UPLOAD_RATE_LIMIT: int = Field(default=60, gt=0)
    UPLOAD_RATE_WINDOW_SECONDS: int = Field(default=3600, gt=0)

    # Inscriptions en libre-service, par adresse IP.
    REGISTRATION_RATE_LIMIT: int = Field(default=5, gt=0)
    REGISTRATION_RATE_WINDOW_SECONDS: int = Field(default=3600, gt=0)

    # ASTRA AI : modèle local Ronda servi par llama-server (llama.cpp).
    # Vide = IA désactivée ; le reste de l'application fonctionne sans.
    AI_BASE_URL: str | None = None
    AI_MODEL: str = "ronda"
    # Un plan complet peut prendre plusieurs minutes sur CPU.
    AI_TIMEOUT_SECONDS: float = Field(default=600, gt=0)
    AI_MAX_CONTEXT_CHARS: int = Field(default=12_000, gt=1_000)
    AI_MAX_OUTPUT_TOKENS: int = Field(default=2_048, gt=0)
    AI_ENABLE_THINKING: bool = False
    # Clé d'API de llama-server (--api-key) quand Ronda est sur un autre serveur.
    AI_API_KEY: str | None = None

    BACKEND_CORS_ORIGINS: Annotated[list[str], NoDecode] = []

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    @classmethod
    def split_cors_origins(cls, value: str | list[str]) -> list[str]:
        if isinstance(value, str):
            value = [origin.strip() for origin in value.split(",") if origin.strip()]
        # Les credentials CORS sont activés : un joker serait dangereux.
        if "*" in value:
            raise ValueError("BACKEND_CORS_ORIGINS ne peut pas contenir '*'.")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
