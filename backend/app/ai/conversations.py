"""Historique ASTRA AI par compte et génération des réponses en arrière-plan.

La réponse de Ronda est produite hors de la requête HTTP : le membre peut
quitter la conversation ou en ouvrir une nouvelle, la réponse est enregistrée
à la fin et retrouvée à son retour.

Les générations tournent dans le processus de l'API (un seul worker) : toute
réponse encore « en cours » au démarrage a donc été interrompue.
"""

import logging
import uuid
from collections.abc import Callable
from datetime import date, timedelta
from typing import Protocol

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from app.ai import actions as ai_actions
from app.ai import focus as ai_focus
from app.ai import service as ai_service
from app.ai.client import LLMClient
from app.core.config import Settings
from app.db.base import utcnow
from app.models import AIConversation, AIMessage, User
from app.models.enums import AIMessageStatus, AIRole
from app.push import hooks as push_hooks
from app.push.message import AI_REPLY_TYPE, PushMessage
from app.schemas.ai import (
    AIConversationDetail,
    AIConversationSummary,
    AIFocus,
    AIMessagePublic,
    ChatTurn,
)
from app.services.errors import ConflictError, NotFoundError, ServiceError

logger = logging.getLogger(__name__)

HISTORY_TURNS = 6  # derniers messages renvoyés à Ronda comme contexte
TITLE_LENGTH = 80
TURN_MAX_CHARS = 8_000  # borne de ChatTurn.content
INTERRUPTED_REPLY = "Réponse interrompue par un redémarrage du serveur. Reposez la question."
UNEXPECTED_FAILURE = "Ronda n'a pas pu répondre, réessayez."


class JobRunner(Protocol):
    """Exécute une génération hors de la requête (ThreadPoolExecutor en production)."""

    def submit(self, fn: Callable[..., object], /, *args: object) -> object: ...


def _title(question: str) -> str:
    text = " ".join(question.split())
    return text if len(text) <= TITLE_LENGTH else text[: TITLE_LENGTH - 1].rstrip() + "…"


def _is_pending(conversation: AIConversation) -> bool:
    return any(m.status == AIMessageStatus.PENDING for m in conversation.messages)


def to_detail(conversation: AIConversation) -> AIConversationDetail:
    return AIConversationDetail(
        id=conversation.id,
        title=conversation.title,
        created_at=conversation.created_at,
        updated_at=conversation.updated_at,
        is_pending=_is_pending(conversation),
        messages=[AIMessagePublic.model_validate(m) for m in conversation.messages],
    )


def list_for_user(
    db: Session, user: User, *, limit: int, offset: int
) -> list[AIConversationSummary]:
    conversations = list(
        db.scalars(
            select(AIConversation)
            .where(AIConversation.user_id == user.id)
            .order_by(AIConversation.updated_at.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return [
        AIConversationSummary(
            id=c.id,
            title=c.title,
            created_at=c.created_at,
            updated_at=c.updated_at,
            is_pending=_is_pending(c),
        )
        for c in conversations
    ]


def get_owned(db: Session, user: User, conversation_id: uuid.UUID) -> AIConversation:
    """Une conversation n'est visible que par son auteur (404 pour les autres)."""
    conversation = db.get(AIConversation, conversation_id)
    if conversation is None or conversation.user_id != user.id:
        raise NotFoundError("Conversation introuvable.")
    return conversation


def add_question(
    db: Session,
    user: User,
    conversation_id: uuid.UUID | None,
    question: str,
    focus: AIFocus | None = None,
) -> tuple[AIConversation, AIMessage]:
    """Enregistre la question et une réponse « en cours » ; la génération est
    lancée ensuite par l'appelant via `generate_reply`.

    Un écran `focus` que le membre ne peut pas ouvrir est refusé (404)."""
    focus_title = ai_focus.read(db, user, focus).title if focus else None
    if conversation_id is None:
        conversation = AIConversation(user_id=user.id, title=_title(question))
        db.add(conversation)
    else:
        conversation = get_owned(db, user, conversation_id)
        if _is_pending(conversation):
            raise ConflictError("Ronda répond déjà dans cette conversation.")
    now = utcnow()
    reply = AIMessage(
        role=AIRole.ASSISTANT,
        content="",
        sources=[],
        status=AIMessageStatus.PENDING,
        # Juste après la question : l'ordre d'affichage suit created_at.
        created_at=now + timedelta(microseconds=1),
    )
    conversation.messages.extend(
        [
            AIMessage(
                role=AIRole.USER,
                content=question,
                sources=[],
                status=AIMessageStatus.DONE,
                focus_type=focus.type if focus else None,
                focus_id=focus.id if focus else None,
                focus_title=focus_title[:200] if focus_title else None,
                created_at=now,
            ),
            reply,
        ]
    )
    conversation.updated_at = now
    db.commit()
    return conversation, reply


def delete(db: Session, user: User, conversation_id: uuid.UUID) -> None:
    db.delete(get_owned(db, user, conversation_id))
    db.commit()


def _history(earlier: list[AIMessage]) -> list[ChatTurn]:
    """Échanges aboutis uniquement : une question restée sans réponse n'est pas renvoyée."""
    turns: list[ChatTurn] = []
    for question, answer in zip(earlier[::2], earlier[1::2], strict=False):
        if answer.status == AIMessageStatus.DONE:
            turns += [
                ChatTurn(role="user", content=question.content[:TURN_MAX_CHARS]),
                ChatTurn(role="assistant", content=answer.content[:TURN_MAX_CHARS]),
            ]
    return turns[-HISTORY_TURNS:]


def _answer(
    db: Session,
    llm: LLMClient,
    settings: Settings,
    reply: AIMessage,
    today: date,
    utc_offset_minutes: int,
) -> tuple[str, list[dict], AIMessageStatus, dict | None]:
    conversation = db.get_one(AIConversation, reply.conversation_id)
    user = db.get_one(User, conversation.user_id)
    earlier = [m for m in conversation.messages if m.created_at < reply.created_at]
    question = earlier[-1]
    focus = (
        AIFocus(type=question.focus_type, id=question.focus_id)
        if question.focus_type and question.focus_id
        else None
    )
    try:
        answer, draft, context_sources = ai_service.converse(
            db, llm, settings, user, question.content, _history(earlier[:-1]), today, focus
        )
    except ServiceError as exc:
        return exc.detail, [], AIMessageStatus.FAILED, None
    except Exception:
        logger.exception("Génération ASTRA AI en échec (message %s)", reply.id)
        return UNEXPECTED_FAILURE, [], AIMessageStatus.FAILED, None
    content = answer.answer
    action = None
    if draft is not None:
        prepared = ai_actions.prepare(db, user, draft, context_sources, focus, utc_offset_minutes)
        if prepared.note:
            content = f"{content}\n\n{prepared.note}"
        if prepared.action:
            action = prepared.action.model_dump(mode="json")
    sources = [s.model_dump(mode="json") for s in answer.sources]
    return content, sources, AIMessageStatus.DONE, action


def generate_reply(
    session_factory: sessionmaker[Session],
    llm: LLMClient,
    settings: Settings,
    reply_id: uuid.UUID,
    today: date,
    utc_offset_minutes: int = 0,
) -> None:
    """Tâche de fond : produit la réponse puis l'enregistre, même si le membre
    a quitté la conversation. Sans effet si elle a été supprimée entre-temps."""
    with session_factory() as db:
        reply = db.get(AIMessage, reply_id)
        if reply is None or reply.status != AIMessageStatus.PENDING:
            return
        content, sources, status, action = _answer(
            db, llm, settings, reply, today, utc_offset_minutes
        )
        conversation_id = reply.conversation_id
        conversation = db.get(AIConversation, conversation_id)
        owner_id, title = conversation.user_id, conversation.title
        db.rollback()  # termine la lecture ; les écritures ci-dessous sont ciblées
        stored = db.execute(
            update(AIMessage)
            .where(AIMessage.id == reply_id, AIMessage.status == AIMessageStatus.PENDING)
            .values(
                content=content,
                sources=sources,
                status=status,
                action=action,
                updated_at=utcnow(),
            )
        )
        db.execute(
            update(AIConversation)
            .where(AIConversation.id == conversation_id)
            .values(updated_at=utcnow())
        )
        if stored.rowcount:
            _push_reply(db, owner_id, conversation_id, title, status)
        db.commit()


def _push_reply(
    db: Session,
    owner_id: uuid.UUID,
    conversation_id: uuid.UUID,
    title: str,
    status: AIMessageStatus,
) -> None:
    """Le membre a souvent quitté l'app pendant la génération (CPU)."""
    headline = "Ronda a répondu" if status == AIMessageStatus.DONE else "Ronda n'a pas pu répondre"
    push_hooks.enqueue(
        db,
        {owner_id},
        PushMessage(
            title=headline,
            body=title,
            type=AI_REPLY_TYPE,
            entity_type="ai_conversation",
            entity_id=conversation_id,
        ),
    )


def fail_interrupted(db: Session) -> int:
    """Au démarrage : les réponses « en cours » ne seront jamais terminées."""
    result = db.execute(
        update(AIMessage)
        .where(AIMessage.status == AIMessageStatus.PENDING)
        .values(content=INTERRUPTED_REPLY, status=AIMessageStatus.FAILED, updated_at=utcnow())
    )
    db.commit()
    return result.rowcount
