"""WebSocket temps réel.

Protocole :
1. le client se connecte à /api/v1/ws puis envoie {"type": "auth", "token": "<access>"}
   (le token n'est jamais mis dans l'URL, qui finit dans les logs) ;
2. le serveur répond {"type": "ready"} puis pousse les événements
   (message.created|updated|deleted, notification.created) ;
3. la connexion est fermée (code 4001) à l'expiration de l'access token :
   le client se reconnecte avec un token rafraîchi.
"""

import json
from datetime import UTC, datetime

import anyio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.core.security import InvalidTokenError, decode_access_token_with_expiry
from app.db.session import get_session_factory
from app.models import User
from app.realtime.hub import hub

router = APIRouter()

AUTH_TIMEOUT_SECONDS = 10
CLOSE_UNAUTHORIZED = 4001


def _load_active_user(user_id) -> bool:
    with get_session_factory()() as db:
        user = db.get(User, user_id)
        return user is not None and user.is_active


async def _authenticate(websocket: WebSocket):
    with anyio.fail_after(AUTH_TIMEOUT_SECONDS):
        raw = await websocket.receive_text()
    message = json.loads(raw)
    if not isinstance(message, dict) or message.get("type") != "auth":
        raise InvalidTokenError
    user_id, expires_at = decode_access_token_with_expiry(str(message.get("token")), get_settings())
    if not await run_in_threadpool(_load_active_user, user_id):
        raise InvalidTokenError
    return user_id, expires_at


@router.websocket("/ws")
async def realtime(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        user_id, expires_at = await _authenticate(websocket)
    except (InvalidTokenError, TimeoutError, ValueError, WebSocketDisconnect):
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return

    queue = hub.connect(user_id)
    await websocket.send_json({"type": "ready"})
    try:
        async with anyio.create_task_group() as tasks:

            async def send_events() -> None:
                while True:
                    await websocket.send_json(await queue.get())

            async def drain_client() -> None:
                # Les messages entrants (pings) sont ignorés ; sert à détecter
                # la déconnexion.
                while True:
                    await websocket.receive_text()

            async def expire() -> None:
                remaining = (expires_at - datetime.now(UTC)).total_seconds()
                await anyio.sleep(max(remaining, 0))
                await websocket.close(code=CLOSE_UNAUTHORIZED)
                tasks.cancel_scope.cancel()

            tasks.start_soon(send_events)
            tasks.start_soon(drain_client)
            tasks.start_soon(expire)
    except* WebSocketDisconnect:
        pass
    finally:
        hub.disconnect(user_id, queue)
