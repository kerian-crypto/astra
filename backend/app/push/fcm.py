"""Client Firebase Cloud Messaging (API HTTP v1).

L'authentification utilise le compte de service du projet Firebase : son
fichier JSON est un secret, fourni par FIREBASE_CREDENTIALS_FILE et jamais
versionné.
"""

import json
import logging
import threading
from enum import StrEnum
from pathlib import Path
from typing import Any, Protocol

import httpx
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account

from app.push.message import PushMessage

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_SEND_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
REQUEST_TIMEOUT_SECONDS = 10.0

# Jetons à oublier : application désinstallée, ou jeton d'un autre projet.
_DEAD_TOKEN_CODES = {"UNREGISTERED", "SENDER_ID_MISMATCH"}


class FirebaseConfigError(RuntimeError):
    """Fichier de compte de service absent ou invalide."""


class SendResult(StrEnum):
    SENT = "sent"
    INVALID_TOKEN = "invalid_token"  # noqa: S105 (statut, pas un secret)
    FAILED = "failed"


class AccessTokenSource(Protocol):
    def access_token(self) -> str: ...


class ServiceAccountTokens:
    """Jeton OAuth2 du compte de service, renouvelé avant expiration."""

    def __init__(self, credentials: service_account.Credentials) -> None:
        self._credentials = credentials
        self._lock = threading.Lock()

    def access_token(self) -> str:
        with self._lock:
            if not self._credentials.valid:
                self._credentials.refresh(GoogleAuthRequest())
            return self._credentials.token


def build_payload(token: str, message: PushMessage) -> dict[str, Any]:
    notification = {"title": message.title}
    if message.body:
        notification["body"] = message.body
    return {
        "message": {
            "token": token,
            "notification": notification,
            "data": message.data(),
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": message.channel.value},
            },
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }


def _error_code(response: httpx.Response) -> tuple[str | None, str]:
    try:
        error = response.json().get("error", {})
    except (json.JSONDecodeError, AttributeError):
        return None, response.text[:200]
    codes = [d.get("errorCode") for d in error.get("details", []) if isinstance(d, dict)]
    return next((c for c in codes if c), error.get("status")), error.get("message", "")


class FcmSender:
    def __init__(self, project_id: str, tokens: AccessTokenSource, http: httpx.Client) -> None:
        self._url = FCM_SEND_URL.format(project_id=project_id)
        self._tokens = tokens
        self._http = http

    @classmethod
    def from_service_account_file(cls, path: str) -> "FcmSender":
        file = Path(path)
        try:
            info = json.loads(file.read_text(encoding="utf-8"))
            credentials = service_account.Credentials.from_service_account_info(
                info, scopes=[FCM_SCOPE]
            )
        except (OSError, ValueError) as error:
            raise FirebaseConfigError(
                f"Compte de service Firebase illisible ({file.name}) : {error}"
            ) from None
        project_id = info.get("project_id")
        if not project_id:
            raise FirebaseConfigError("Le compte de service Firebase n'indique pas project_id.")
        http = httpx.Client(timeout=REQUEST_TIMEOUT_SECONDS)
        return cls(project_id, ServiceAccountTokens(credentials), http)

    def send(self, token: str, message: PushMessage) -> SendResult:
        try:
            response = self._http.post(
                self._url,
                json=build_payload(token, message),
                headers={"Authorization": f"Bearer {self._tokens.access_token()}"},
            )
        except (httpx.HTTPError, OSError) as error:
            logger.warning("Envoi FCM impossible : %s", type(error).__name__)
            return SendResult.FAILED
        except GoogleAuthError as error:
            logger.error("Authentification FCM impossible : %s", error)
            return SendResult.FAILED
        if response.is_success:
            return SendResult.SENT
        code, detail = _error_code(response)
        is_bad_token = code == "INVALID_ARGUMENT" and "registration token" in detail
        if code in _DEAD_TOKEN_CODES or is_bad_token:
            return SendResult.INVALID_TOKEN
        # Le jeton de l'appareil n'est jamais journalisé.
        logger.warning("FCM a refusé l'envoi (%s, %s) : %s", response.status_code, code, detail)
        return SendResult.FAILED

    def close(self) -> None:
        self._http.close()
