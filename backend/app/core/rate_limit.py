import time
from collections import defaultdict, deque
from threading import Lock


class SlidingWindowRateLimiter:
    """Limiteur en mémoire, par clé, sur une fenêtre glissante.

    Suffisant pour un seul processus API. Avec plusieurs workers ou
    instances, il faudra le remplacer par un stockage partagé (Redis).
    """

    # Balayage complet au plus une fois par fenêtre : les clés expirées sont
    # oubliées, sinon des milliers de clés inventées (emails, IP) rempliraient
    # la mémoire.
    def __init__(self, max_attempts: int, window_seconds: int) -> None:
        self._max_attempts = max_attempts
        self._window_seconds = window_seconds
        self._attempts: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()
        self._last_sweep = time.monotonic()

    def _expire(self, attempts: deque[float], now: float) -> None:
        while attempts and now - attempts[0] >= self._window_seconds:
            attempts.popleft()

    def _sweep(self, now: float) -> None:
        if now - self._last_sweep < self._window_seconds:
            return
        self._last_sweep = now
        for key in list(self._attempts):
            self._expire(self._attempts[key], now)
            if not self._attempts[key]:
                del self._attempts[key]

    def _count(self, key: str, now: float) -> int:
        self._sweep(now)
        attempts = self._attempts.get(key)
        if attempts is None:
            return 0
        self._expire(attempts, now)
        if not attempts:
            del self._attempts[key]
            return 0
        return len(attempts)

    def is_blocked(self, key: str) -> bool:
        with self._lock:
            return self._count(key, time.monotonic()) >= self._max_attempts

    def record_failure(self, key: str) -> None:
        with self._lock:
            now = time.monotonic()
            self._count(key, now)
            self._attempts[key].append(now)

    def tracked_keys(self) -> int:
        with self._lock:
            now = time.monotonic()
            self._last_sweep = now - self._window_seconds  # force le balayage
            self._sweep(now)
            return len(self._attempts)

    def reset(self, key: str) -> None:
        with self._lock:
            self._attempts.pop(key, None)
