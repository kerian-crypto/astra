"""Routes d'administration du domaine client, utilisées par Astra Hub."""

from fastapi import APIRouter

from app.api.v1.clients import billing, briefs, companies, conversations, deliverables, tickets


def build_router() -> APIRouter:
    router = APIRouter()
    for module in (companies, briefs, conversations, tickets, billing, deliverables):
        router.include_router(module.router)
    return router
