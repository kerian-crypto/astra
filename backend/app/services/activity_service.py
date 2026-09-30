"""Journal d'activité (« qui a fait quoi, quand »).

`record` ajoute l'entrée à la session sans commit : elle est enregistrée dans
la même transaction que la modification qu'elle décrit.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ActivityLog, User


def _jsonable(value: Any) -> Any:
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, uuid.UUID | Decimal):
        return str(value)
    if isinstance(value, date | datetime):
        return value.isoformat()
    if isinstance(value, list | tuple):
        return [_jsonable(v) for v in value]
    return value


def diff(entity: object, changes: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Calcule {champ: {"from": ancien, "to": nouveau}} pour les champs modifiés,
    avant application des changements sur l'entité."""
    result = {}
    for field, new_value in changes.items():
        old_value = getattr(entity, field)
        if old_value != new_value:
            result[field] = {"from": _jsonable(old_value), "to": _jsonable(new_value)}
    return result


def record(
    db: Session,
    *,
    actor: User | None,
    entity_type: str,
    entity_id: uuid.UUID,
    action: str,
    project_id: uuid.UUID | None = None,
    changes: dict[str, Any] | None = None,
) -> None:
    db.add(
        ActivityLog(
            project_id=project_id,
            actor_id=actor.id if actor else None,
            entity_type=entity_type,
            entity_id=entity_id,
            action=action,
            changes={k: _jsonable(v) for k, v in (changes or {}).items()},
        )
    )


def list_for_entity(db: Session, entity_id: uuid.UUID, limit: int = 100) -> list[ActivityLog]:
    return list(
        db.scalars(
            select(ActivityLog)
            .where(ActivityLog.entity_id == entity_id)
            .order_by(ActivityLog.created_at.desc())
            .limit(limit)
        )
    )


def list_for_project(
    db: Session, project_id: uuid.UUID, *, limit: int, offset: int
) -> list[ActivityLog]:
    return list(
        db.scalars(
            select(ActivityLog)
            .where(ActivityLog.project_id == project_id)
            .order_by(ActivityLog.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
    )
