import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status

from app.ai import actions as ai_actions
from app.ai import conversations
from app.ai import service as ai_service
from app.ai.client import AIUnavailableError, LlamaServerClient, LLMClient
from app.api.deps import AppSettings, CurrentUser, DbSession
from app.core.config import Settings, get_settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.db.session import get_session_factory
from app.schemas.ai import (
    ActionDecision,
    AIConversationDetail,
    AIConversationSummary,
    AIMessagePublic,
    AIStatus,
    AskRequest,
    AskResponse,
    ConversationQuestion,
    HealthReport,
    MeetingSummaryProposal,
    PlanProposal,
    PlanRequest,
)
from app.services import insights_service, meeting_service
from app.services.errors import RateLimitedError

router = APIRouter(prefix="/ai", tags=["ai"])

AI_REQUESTS_PER_WINDOW = 30
AI_WINDOW_SECONDS = 3600

_clients: dict[tuple[str, str, str], LlamaServerClient] = {}


def get_llm(settings: Annotated[Settings, Depends(get_settings)]) -> LLMClient | None:
    """Un client (et donc une file d'attente) par serveur Ronda configuré."""
    if not settings.AI_BASE_URL:
        return None
    key = (settings.AI_BASE_URL, settings.AI_MODEL, settings.AI_API_KEY or "")
    if key not in _clients:
        _clients[key] = LlamaServerClient(
            settings.AI_BASE_URL,
            settings.AI_MODEL,
            settings.AI_TIMEOUT_SECONDS,
            enable_thinking=settings.AI_ENABLE_THINKING,
            api_key=settings.AI_API_KEY,
        )
    return _clients[key]


OptionalLLM = Annotated[LLMClient | None, Depends(get_llm)]


def _limiter(request: Request) -> SlidingWindowRateLimiter:
    return request.app.state.ai_limiter


def require_llm(
    llm: OptionalLLM,
    user: CurrentUser,
    limiter: Annotated[SlidingWindowRateLimiter, Depends(_limiter)],
) -> LLMClient:
    if llm is None:
        raise AIUnavailableError("ASTRA AI n'est pas configurée sur ce serveur.")
    key = str(user.id)
    if limiter.is_blocked(key):
        raise RateLimitedError("Trop de demandes à ASTRA AI. Réessayez plus tard.")
    limiter.record_failure(key)  # compte chaque appel, réussi ou non
    return llm


LLM = Annotated[LLMClient, Depends(require_llm)]


def _jobs(request: Request) -> conversations.JobRunner:
    return request.app.state.ai_jobs


Jobs = Annotated[conversations.JobRunner, Depends(_jobs)]


def _today(today: date | None) -> date:
    return today or date.today()


@router.get("/status", response_model=AIStatus)
def ai_status(_: CurrentUser, llm: OptionalLLM, settings: AppSettings) -> AIStatus:
    return AIStatus(
        enabled=llm is not None,
        reachable=llm.is_reachable() if llm else False,
        model=settings.AI_MODEL if llm else None,
    )


@router.post("/ask", response_model=AskResponse)
def ask(
    body: AskRequest,
    user: CurrentUser,
    db: DbSession,
    llm: LLM,
    settings: AppSettings,
    today: date | None = None,
) -> AskResponse:
    return ai_service.ask(db, llm, settings, user, body.question, body.history, _today(today))


@router.post("/plan", response_model=PlanProposal)
def propose_plan(
    body: PlanRequest, _: CurrentUser, llm: LLM, settings: AppSettings
) -> PlanProposal:
    """Proposition seulement : la création passe par POST /projects/from-plan."""
    return ai_service.propose_plan(llm, settings, body.idea)


@router.post("/meetings/{meeting_id}/summary", response_model=MeetingSummaryProposal)
def summarize_meeting(
    meeting_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    llm: LLM,
    settings: AppSettings,
    today: date | None = None,
) -> MeetingSummaryProposal:
    meeting = meeting_service.get_accessible_meeting(db, user, meeting_id)
    return ai_service.summarize_meeting(llm, settings, meeting, _today(today))


@router.get("/health-report", response_model=HealthReport)
def health_report(
    user: CurrentUser, db: DbSession, llm: LLM, settings: AppSettings, today: date | None = None
) -> HealthReport:
    health = insights_service.health(db, user, _today(today))
    return HealthReport(report=ai_service.health_report(llm, settings, health))


# ---------- Historique des conversations ----------


def _ask_in_conversation(
    conversation_id: uuid.UUID | None,
    body: ConversationQuestion,
    user: CurrentUser,
    db: DbSession,
    llm: LLMClient,
    settings: Settings,
    jobs: conversations.JobRunner,
    today: date,
) -> AIConversationDetail:
    conversation, reply = conversations.add_question(
        db, user, conversation_id, body.question, body.focus
    )
    jobs.submit(
        conversations.generate_reply,
        get_session_factory(),
        llm,
        settings,
        reply.id,
        today,
        body.utc_offset_minutes,
    )
    db.expire_all()  # la réponse peut déjà avoir été écrite par une autre session
    return conversations.to_detail(conversation)


@router.get("/conversations", response_model=list[AIConversationSummary])
def list_conversations(
    user: CurrentUser,
    db: DbSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[AIConversationSummary]:
    return conversations.list_for_user(db, user, limit=limit, offset=offset)


@router.post(
    "/conversations", response_model=AIConversationDetail, status_code=status.HTTP_201_CREATED
)
def start_conversation(
    body: ConversationQuestion,
    user: CurrentUser,
    db: DbSession,
    llm: LLM,
    settings: AppSettings,
    jobs: Jobs,
    today: date | None = None,
) -> AIConversationDetail:
    """Crée la conversation ; la réponse de Ronda arrive en arrière-plan
    (message `pending`, à relire via GET /ai/conversations/{id})."""
    return _ask_in_conversation(None, body, user, db, llm, settings, jobs, _today(today))


@router.get("/conversations/{conversation_id}", response_model=AIConversationDetail)
def get_conversation(
    conversation_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> AIConversationDetail:
    return conversations.to_detail(conversations.get_owned(db, user, conversation_id))


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=AIConversationDetail,
    status_code=status.HTTP_201_CREATED,
)
def continue_conversation(
    conversation_id: uuid.UUID,
    body: ConversationQuestion,
    user: CurrentUser,
    db: DbSession,
    llm: LLM,
    settings: AppSettings,
    jobs: Jobs,
    today: date | None = None,
) -> AIConversationDetail:
    return _ask_in_conversation(conversation_id, body, user, db, llm, settings, jobs, _today(today))


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(conversation_id: uuid.UUID, user: CurrentUser, db: DbSession) -> None:
    conversations.delete(db, user, conversation_id)


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/action",
    response_model=AIMessagePublic,
)
def decide_action(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    body: ActionDecision,
    user: CurrentUser,
    db: DbSession,
) -> AIMessagePublic:
    """Le membre valide (exécution avec ses droits) ou écarte l'action proposée."""
    message = ai_actions.decide(db, user, conversation_id, message_id, body.apply)
    return AIMessagePublic.model_validate(message)
