"""Journal d'audit des actions client (§42), dans `activity_logs` : les
actions d'un client apparaissent dans l'historique du projet côté Hub."""

import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.models import ActivityLog, ClientAccount
from app.services.activity_service import jsonable


def record(
    db: Session,
    account: ClientAccount,
    *,
    entity_type: str,
    entity_id: uuid.UUID,
    action: str,
    project_id: uuid.UUID | None = None,
    changes: dict[str, Any] | None = None,
) -> None:
    """Ajoute l'entrée sans commit (même transaction que l'action)."""
    db.add(
        ActivityLog(
            project_id=project_id,
            client_account_id=account.id,
            client_actor_name=account.full_name,
            entity_type=entity_type,
            entity_id=entity_id,
            action=action,
            changes={
                "company": account.company.name,
                **{k: jsonable(v) for k, v in (changes or {}).items()},
            },
        )
    )
