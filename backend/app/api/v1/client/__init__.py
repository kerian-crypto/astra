"""Routes d'Astra Client, sous /api/v1/client.

Toutes (sauf l'authentification) exigent un jeton client : les jetons des
membres d'Astra y sont refusés, comme les jetons client sur les routes Hub.
"""

from fastapi import APIRouter

from app.api.v1.client import (
    auth,
    billing,
    briefs,
    documents,
    home,
    messages,
    profile,
    projects,
    support,
    ws,
)


def build_router() -> APIRouter:
    router = APIRouter(prefix="/client")
    for module in (
        auth,
        profile,
        home,
        projects,
        documents,
        messages,
        support,
        billing,
        briefs,
        ws,
    ):
        router.include_router(module.router)
    return router
