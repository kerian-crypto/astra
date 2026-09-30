"""Diffusion temps réel vers les connexions WebSocket.

Le hub vit dans la boucle asyncio du processus. Les routes synchrones (qui
tournent dans des threads) publient via `publish_from_thread`.

Limite connue : un hub par processus. Avec plusieurs workers ou instances,
il faudra un bus partagé (Redis pub/sub).
"""

import asyncio
import logging
import uuid
from collections import defaultdict
from typing import Any

import anyio.from_thread

logger = logging.getLogger(__name__)

QUEUE_SIZE = 200

Event = dict[str, Any]


class RealtimeHub:
    def __init__(self) -> None:
        self._queues: dict[uuid.UUID, set[asyncio.Queue[Event]]] = defaultdict(set)

    def connect(self, user_id: uuid.UUID) -> asyncio.Queue[Event]:
        queue: asyncio.Queue[Event] = asyncio.Queue(maxsize=QUEUE_SIZE)
        self._queues[user_id].add(queue)
        return queue

    def disconnect(self, user_id: uuid.UUID, queue: asyncio.Queue[Event]) -> None:
        self._queues[user_id].discard(queue)
        if not self._queues[user_id]:
            del self._queues[user_id]

    def connected_users(self) -> set[uuid.UUID]:
        return set(self._queues)

    def publish(self, event: Event, user_ids: set[uuid.UUID]) -> None:
        """À appeler depuis la boucle asyncio. Un client trop lent perd des
        événements plutôt que de bloquer les autres : il resynchronise via l'API."""
        for user_id in user_ids & self.connected_users():
            for queue in self._queues[user_id]:
                try:
                    queue.put_nowait(event)
                except asyncio.QueueFull:
                    logger.warning("File temps réel pleine (user=%s), événement ignoré", user_id)


hub = RealtimeHub()


def publish_from_thread(event: Event, user_ids: set[uuid.UUID]) -> None:
    """Publie depuis un thread de travail AnyIO (route synchrone). Hors d'un
    tel contexte (CLI, scripts), le temps réel est simplement ignoré."""
    if not user_ids:
        return
    try:
        anyio.from_thread.run_sync(hub.publish, event, user_ids)
    except RuntimeError:
        logger.debug("Publication temps réel ignorée hors du serveur")
