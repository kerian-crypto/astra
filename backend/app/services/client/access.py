"""Règles d'autorisation d'Astra Client.

Toute donnée renvoyée à un compte client passe par ce module. Deux règles
non négociables (cahier des charges §11, §39) :

1. Isolation : chaque requête est filtrée par l'entreprise du compte. Une
   ressource d'une autre entreprise répond 404, comme une ressource inexistante.
2. Permissions : chaque action exige une permission explicite du compte.
   Une permission manquante répond 403.
"""

import uuid

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from app.models import ClientAccount, Deliverable, Project
from app.models.client_enums import ClientPermission, DeliverableStatus
from app.services.errors import NotFoundError, PermissionDeniedError

PROJECT_NOT_FOUND = "Projet introuvable."
DELIVERABLE_NOT_FOUND = "Livrable introuvable."
MISSING_PERMISSION = "Votre compte n'a pas l'autorisation d'effectuer cette action."


def require(account: ClientAccount, permission: ClientPermission) -> None:
    if not account.has_permission(permission):
        raise PermissionDeniedError(MISSING_PERMISSION)


def company_projects_statement(account: ClientAccount) -> Select[tuple[Project]]:
    """Projets de l'entreprise du compte, et d'elle seule."""
    return select(Project).where(Project.client_company_id == account.company_id)


def company_project_ids(account: ClientAccount) -> Select[tuple[uuid.UUID]]:
    return select(Project.id).where(Project.client_company_id == account.company_id)


def get_project(db: Session, account: ClientAccount, project_id: uuid.UUID) -> Project:
    require(account, ClientPermission.VIEW_PROJECT)
    project = db.scalar(company_projects_statement(account).where(Project.id == project_id))
    if project is None:
        raise NotFoundError(PROJECT_NOT_FOUND)
    return project


def visible_deliverables_statement(account: ClientAccount) -> Select[tuple[Deliverable]]:
    """Livrables publiés des projets de l'entreprise (jamais les brouillons)."""
    return select(Deliverable).where(
        Deliverable.project_id.in_(company_project_ids(account)),
        Deliverable.status != DeliverableStatus.DRAFT,
    )


def get_deliverable(db: Session, account: ClientAccount, deliverable_id: uuid.UUID) -> Deliverable:
    require(account, ClientPermission.VIEW_PROJECT)
    deliverable = db.scalar(
        visible_deliverables_statement(account).where(Deliverable.id == deliverable_id)
    )
    if deliverable is None:
        raise NotFoundError(DELIVERABLE_NOT_FOUND)
    return deliverable


def recipients(
    db: Session, company_id: uuid.UUID, permission: ClientPermission | None = None
) -> list[uuid.UUID]:
    """Comptes actifs et activés d'une entreprise, éventuellement filtrés par
    permission : destinataires des notifications client."""
    statement = select(ClientAccount.id).where(
        ClientAccount.company_id == company_id,
        ClientAccount.is_active.is_(True),
        ClientAccount.activated_at.is_not(None),
    )
    if permission is not None:
        statement = statement.where(ClientAccount.permissions.contains([permission.value]))
    return list(db.scalars(statement))
