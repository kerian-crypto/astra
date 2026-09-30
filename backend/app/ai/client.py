"""Client du modèle local Ronda, servi par llama-server (llama.cpp).

Utilise l'endpoint compatible `/v1/chat/completions` de llama-server, qui
applique le modèle de conversation du modèle et sait contraindre la sortie
à un schéma JSON (grammaire générée côté serveur).
"""

import logging
import re
import threading
from typing import Any, Protocol

import httpx

from app.services.errors import ServiceError

logger = logging.getLogger(__name__)

# Un modèle local sur CPU traite une requête à la fois : les suivantes
# attendent un peu, puis reçoivent « occupée » plutôt que de s'empiler.
QUEUE_WAIT_SECONDS = 60
_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL)

Message = dict[str, str]


class AIUnavailableError(ServiceError):
    status_code = 503


class AIResponseError(ServiceError):
    status_code = 502


class LLMClient(Protocol):
    def chat(
        self,
        messages: list[Message],
        *,
        max_tokens: int,
        json_schema: dict[str, Any] | None = None,
    ) -> str: ...

    def is_reachable(self) -> bool: ...


class LlamaServerClient:
    def __init__(
        self,
        base_url: str,
        model: str,
        timeout_seconds: float,
        *,
        enable_thinking: bool = False,
        api_key: str | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        # Ronda hébergée à distance : llama-server lancé avec --api-key.
        self._headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        self._model = model
        self._timeout = timeout_seconds
        self._enable_thinking = enable_thinking
        self._slot = threading.BoundedSemaphore(1)

    def is_reachable(self) -> bool:
        try:
            return httpx.get(f"{self._base_url}/health", timeout=3).status_code == 200
        except httpx.HTTPError:
            return False

    def chat(
        self,
        messages: list[Message],
        *,
        max_tokens: int,
        json_schema: dict[str, Any] | None = None,
    ) -> str:
        payload: dict[str, Any] = {
            "model": self._model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": max_tokens,
            "stream": False,
            # Qwen3.5 réfléchit par défaut : sur CPU, la réflexion peut consommer
            # tout le budget de tokens avant la réponse. Désactivée sauf réglage.
            "chat_template_kwargs": {"enable_thinking": self._enable_thinking},
        }
        if json_schema is not None:
            payload["response_format"] = {
                "type": "json_schema",
                "json_schema": {"name": "reponse", "schema": json_schema, "strict": True},
            }
        if not self._slot.acquire(timeout=QUEUE_WAIT_SECONDS):
            raise AIUnavailableError("Ronda est occupée, réessayez dans un instant.")
        try:
            response = httpx.post(
                f"{self._base_url}/v1/chat/completions",
                json=payload,
                timeout=self._timeout,
                headers=self._headers,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"].get("content") or ""
        except httpx.TimeoutException:
            raise AIUnavailableError("Ronda met trop de temps à répondre.") from None
        except httpx.HTTPError as exc:
            logger.warning("Ronda injoignable ou en erreur : %s", exc)
            raise AIUnavailableError("Ronda est injoignable pour le moment.") from None
        except (KeyError, IndexError, ValueError) as exc:
            raise AIResponseError("Réponse de Ronda illisible.") from exc
        finally:
            self._slot.release()
        # Les modèles « à réflexion » peuvent laisser leur brouillon dans le texte.
        return _THINK_BLOCK.sub("", content).strip()
