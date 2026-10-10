"""Envoi des notifications push hors du cycle des requêtes.

Les routes ne font qu'empiler les envois ; un unique thread les transmet à
FCM. Un appareil injoignable ne ralentit donc jamais l'API.
"""

import logging
import uuid
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from typing import Protocol

from sqlalchemy import delete, select
from sqlalchemy.orm import Session, sessionmaker

from app.models import ClientAccount, ClientDeviceToken, DeviceToken, User
from app.push.fcm import SendResult
from app.push.message import PushAudience, PushMessage

logger = logging.getLogger(__name__)


class PushSender(Protocol):
    def send(self, token: str, message: PushMessage) -> SendResult: ...

    def close(self) -> None: ...


class PushSink(Protocol):
    def submit(self, user_ids: frozenset[uuid.UUID], message: PushMessage) -> None: ...


class PushDispatcher:
    """`sender` : projet Firebase d'Astra Hub ; `client_sender` : projet
    Firebase d'Astra Client. Un jeton n'est valable que pour son projet :
    chaque audience a donc son propre émetteur (absent = push désactivé)."""

    def __init__(
        self,
        session_factory: sessionmaker[Session],
        sender: PushSender | None,
        client_sender: PushSender | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._sender = sender
        self._client_sender = client_sender
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="push")

    def submit(self, user_ids: frozenset[uuid.UUID], message: PushMessage) -> None:
        self._executor.submit(self._deliver_safely, user_ids, message)

    def shutdown(self) -> None:
        self._executor.shutdown(wait=False, cancel_futures=True)
        for sender in (self._sender, self._client_sender):
            if sender is not None:
                sender.close()

    def _deliver_safely(self, user_ids: frozenset[uuid.UUID], message: PushMessage) -> None:
        try:
            self.deliver(user_ids, message)
        except Exception:
            # Un envoi raté ne doit pas arrêter le thread des suivants.
            logger.exception("Échec de l'envoi push")

    def deliver(self, user_ids: Iterable[uuid.UUID], message: PushMessage) -> int:
        """Envoie à tous les appareils des membres actifs ; renvoie le nombre
        d'envois réussis et oublie les jetons que FCM déclare invalides."""
        is_client = message.audience == PushAudience.CLIENT
        sender = self._client_sender if is_client else self._sender
        if sender is None:
            return 0
        table = ClientDeviceToken if is_client else DeviceToken
        with self._session_factory() as db:
            if is_client:
                query = (
                    select(ClientDeviceToken.id, ClientDeviceToken.token)
                    .join(ClientAccount, ClientAccount.id == ClientDeviceToken.account_id)
                    .where(
                        ClientDeviceToken.account_id.in_(set(user_ids)),
                        ClientAccount.is_active.is_(True),
                    )
                )
            else:
                query = (
                    select(DeviceToken.id, DeviceToken.token)
                    .join(User, User.id == DeviceToken.user_id)
                    .where(DeviceToken.user_id.in_(set(user_ids)), User.is_active.is_(True))
                )
            devices = db.execute(query).all()
            results = {device_id: sender.send(token, message) for device_id, token in devices}
            dead = [
                device_id
                for device_id, result in results.items()
                if result == SendResult.INVALID_TOKEN
            ]
            if dead:
                db.execute(delete(table).where(table.id.in_(dead)))
                db.commit()
        return sum(result == SendResult.SENT for result in results.values())


_sink: PushSink | None = None


def configure(sink: PushSink | None) -> None:
    """None désactive le push (Firebase non configuré)."""
    global _sink
    _sink = sink


def submit(user_ids: Iterable[uuid.UUID], message: PushMessage) -> None:
    recipients = frozenset(user_ids)
    if _sink is not None and recipients:
        _sink.submit(recipients, message)
