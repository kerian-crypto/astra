from collections.abc import AsyncIterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.ai import conversations as ai_conversations
from app.api.deps import DbSession
from app.api.v1 import (
    ai,
    auth,
    chat,
    decisions,
    documents,
    insights,
    meetings,
    notifications,
    projects,
    registration,
    tasks,
    users,
    work,
    ws,
)
from app.core.config import Settings, get_settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.db.session import get_session_factory
from app.realtime import notifications as realtime_notifications
from app.services.errors import ServiceError


def _service_error_handler(_: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, ServiceError):
        raise exc
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


def _build_api_router() -> APIRouter:
    router = APIRouter()
    router.include_router(auth.router)
    # Avant `users` : /users/pending doit primer sur /users/{user_id}.
    router.include_router(registration.router)
    router.include_router(users.router)
    router.include_router(projects.router)
    router.include_router(tasks.router)
    router.include_router(work.router)
    router.include_router(meetings.router)
    router.include_router(decisions.router)
    router.include_router(chat.router)
    router.include_router(notifications.router)
    router.include_router(ws.router)
    router.include_router(documents.router)
    router.include_router(insights.router)
    router.include_router(ai.router)
    return router


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    with get_session_factory()() as db:
        ai_conversations.fail_interrupted(db)
    # Réponses ASTRA AI générées hors requête, une à la fois (Ronda sur CPU).
    executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="ronda")
    app.state.ai_jobs = executor
    yield
    executor.shutdown(wait=False, cancel_futures=True)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    is_production = settings.ENVIRONMENT == "production"

    app = FastAPI(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        openapi_url=None if is_production else f"{settings.API_V1_STR}/openapi.json",
        docs_url=None if is_production else "/docs",
        redoc_url=None,
        lifespan=_lifespan,
    )
    app.state.login_limiter = SlidingWindowRateLimiter(
        settings.LOGIN_RATE_LIMIT_ATTEMPTS, settings.LOGIN_RATE_LIMIT_WINDOW_SECONDS
    )
    app.state.registration_limiter = SlidingWindowRateLimiter(
        settings.REGISTRATION_RATE_LIMIT, settings.REGISTRATION_RATE_WINDOW_SECONDS
    )
    app.state.ai_limiter = SlidingWindowRateLimiter(ai.AI_REQUESTS_PER_WINDOW, ai.AI_WINDOW_SECONDS)
    app.state.upload_limiter = SlidingWindowRateLimiter(
        settings.UPLOAD_RATE_LIMIT, settings.UPLOAD_RATE_WINDOW_SECONDS
    )

    if settings.BACKEND_CORS_ORIGINS:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.BACKEND_CORS_ORIGINS,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )

    realtime_notifications.install()
    app.add_exception_handler(ServiceError, _service_error_handler)
    app.include_router(_build_api_router(), prefix=settings.API_V1_STR)

    @app.get("/health", tags=["system"])
    def health(db: DbSession) -> dict[str, str]:
        db.execute(text("SELECT 1"))
        return {"status": "healthy"}

    return app
