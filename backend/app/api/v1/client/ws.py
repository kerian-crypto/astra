"""WebSocket Astra Client : même protocole que /ws, jetons client uniquement.

Événements : message.created, notification.created.
"""

import json

import anyio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool

from app.api.v1.ws import AUTH_TIMEOUT_SECONDS, CLOSE_UNAUTHORIZED, serve_session
from app.core.config import get_settings
from app.core.security import InvalidTokenError, decode_client_access_token_with_expiry
from app.db.session import get_session_factory
from app.models import ClientAccount
from app.realtime.hub import client_hub
from app.services.client import auth as client_auth

router = APIRouter()


def _load_usable_account(account_id) -> bool:
    with get_session_factory()() as db:
        return client_auth.is_usable(db.get(ClientAccount, account_id))


async def _authenticate(websocket: WebSocket):
    with anyio.fail_after(AUTH_TIMEOUT_SECONDS):
        raw = await websocket.receive_text()
    message = json.loads(raw)
    if not isinstance(message, dict) or message.get("type") != "auth":
        raise InvalidTokenError
    account_id, expires_at = decode_client_access_token_with_expiry(
        str(message.get("token")), get_settings()
    )
    if not await run_in_threadpool(_load_usable_account, account_id):
        raise InvalidTokenError
    return account_id, expires_at


@router.websocket("/ws")
async def realtime(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        account_id, expires_at = await _authenticate(websocket)
    except (InvalidTokenError, TimeoutError, ValueError, WebSocketDisconnect):
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return
    await serve_session(websocket, client_hub, account_id, expires_at)
