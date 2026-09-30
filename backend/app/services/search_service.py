"""Recherche dans Astra (spec §16), restreinte à ce que l'utilisateur peut voir.

Chaque source applique le même filtre de visibilité que son module : la
recherche (et l'IA qui s'en sert) n'est jamais une porte d'accès supplémentaire.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from sqlalchemy import ColumnElement, Select, func, literal_column, select
from sqlalchemy.orm import Session

from app.models import Decision, Document, Meeting, Message, Project, Task, User
from app.schemas.search import SearchHit, SearchType
from app.services import (
    channel_service,
    decision_service,
    document_service,
    meeting_service,
    permissions,
)

LANGUAGE = literal_column("'french'::regconfig")
PER_TYPE_LIMIT = 10
MAX_RESULTS = 30
HEADLINE_OPTIONS = "MaxWords=30, MinWords=10, MaxFragments=2, StartSel=«, StopSel=»"


def _text(*columns: Any) -> ColumnElement[str]:
    return func.concat_ws(" ", *[func.coalesce(c, "") for c in columns])


@dataclass(frozen=True)
class _Source:
    type: SearchType
    base: Callable[[User], Select]
    title: Any
    body: ColumnElement[str]
    project_id: Any = None
    parent_id: Any = None
    vector: Any = None  # colonne tsvector indexée, sinon calculée à la volée


def _sources() -> list[_Source]:
    return [
        _Source(
            SearchType.PROJECT,
            permissions.visible_projects_statement,
            Project.name,
            _text(Project.name, Project.description, Project.objective),
            project_id=Project.id,
        ),
        _Source(
            SearchType.TASK,
            lambda user: select(Task).where(
                Task.project_id.in_(permissions.visible_project_ids(user))
            ),
            Task.title,
            _text(Task.title, Task.description),
            project_id=Task.project_id,
        ),
        _Source(
            SearchType.DECISION,
            decision_service.visible_decisions_statement,
            Decision.title,
            _text(Decision.title, Decision.description),
            project_id=Decision.project_id,
            parent_id=Decision.meeting_id,
        ),
        _Source(
            SearchType.MEETING,
            lambda user: select(Meeting).where(
                Meeting.id.in_(meeting_service.visible_meeting_ids(user))
            ),
            Meeting.title,
            _text(Meeting.title, Meeting.agenda, Meeting.minutes),
            project_id=Meeting.project_id,
        ),
        _Source(
            SearchType.DOCUMENT,
            document_service.visible_documents_statement,
            Document.title,
            _text(Document.title, Document.text_content),
            project_id=Document.project_id,
            vector=Document.search_vector,
        ),
        _Source(
            SearchType.MESSAGE,
            lambda user: select(Message).where(
                Message.channel_id.in_(channel_service.visible_channel_ids(user)),
                Message.deleted_at.is_(None),
            ),
            func.left(Message.body, 80),
            Message.body,
            parent_id=Message.channel_id,
        ),
    ]


def _search_source(
    db: Session, user: User, source: _Source, query: ColumnElement
) -> list[SearchHit]:
    vector = source.vector if source.vector is not None else func.to_tsvector(LANGUAGE, source.body)
    rank = func.ts_rank(vector, query)
    entity = source.base(user).column_descriptions[0]["entity"]
    statement = (
        source.base(user)
        .with_only_columns(
            entity.id,
            source.title,
            func.ts_headline(LANGUAGE, source.body, query, HEADLINE_OPTIONS),
            source.project_id if source.project_id is not None else literal_column("NULL"),
            source.parent_id if source.parent_id is not None else literal_column("NULL"),
            rank,
        )
        .where(vector.op("@@")(query))
        .order_by(rank.desc())
        .limit(PER_TYPE_LIMIT)
    )
    return [
        SearchHit(
            type=source.type,
            id=row[0],
            title=row[1] or "",
            snippet=row[2] or "",
            project_id=row[3],
            parent_id=row[4],
            score=float(row[5]),
        )
        for row in db.execute(statement)
    ]


def search(
    db: Session, user: User, text: str, types: set[SearchType] | None = None
) -> list[SearchHit]:
    query = func.websearch_to_tsquery(LANGUAGE, text)
    hits: list[SearchHit] = []
    for source in _sources():
        if types and source.type not in types:
            continue
        hits.extend(_search_source(db, user, source, query))
    return sorted(hits, key=lambda hit: hit.score, reverse=True)[:MAX_RESULTS]
