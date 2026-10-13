"""Suppression de son propre compte depuis Astra Client (exigence Google Play).

Supprimé : le compte et tout ce qui en dépend (sessions, appareils,
notifications, invitations), l'historique de son profil, et son nom dans
l'historique des projets. Conservé : ce qui appartient au dossier de
l'entreprise (messages, documents, factures), auteur effacé par les clés
étrangères `SET NULL`.

L'entreprise disparaît avec son dernier compte seulement si aucune relation
contractuelle n'existe (ni projet, ni facture, ni contrat) : cas du prospect
inscrit depuis l'application.
"""

from sqlalchemy import delete, exists, select, update
from sqlalchemy.orm import Session

from app.core.security import verify_password
from app.core.storage import LocalFileStorage
from app.models import (
    ActivityLog,
    BriefFile,
    ClientAccount,
    ClientCompany,
    ClientConversation,
    ClientMessage,
    Contract,
    Invoice,
    Project,
    ProjectBrief,
)
from app.services.errors import ServiceError

WRONG_PASSWORD = "Mot de passe incorrect."  # noqa: S105 — message, pas un secret
DELETED_ACTOR_NAME = "Compte supprimé"


class WrongPasswordError(ServiceError):
    """400 et non 401 : la session reste valide, l'app ne doit pas la renouveler."""


def delete_own_account(
    db: Session,
    account: ClientAccount,
    password: str,
    storage: LocalFileStorage,
    photo_storage: LocalFileStorage,
) -> None:
    if not account.password_hash or not verify_password(password, account.password_hash):
        raise WrongPasswordError(WRONG_PASSWORD)

    company = account.company
    remove_company = _is_last_account(db, account) and not _has_business_relation(db, company)
    file_keys = _company_file_keys(db, company) if remove_company else []
    logo_key = company.logo_key if remove_company else None

    _forget_in_history(db, account)
    db.delete(account)
    if remove_company:
        db.delete(company)
    db.commit()

    # Fichiers effacés après le commit : une erreur disque ne doit pas annuler la suppression.
    for key in file_keys:
        storage.delete(key)
    if logo_key:
        photo_storage.delete(logo_key)


def _is_last_account(db: Session, account: ClientAccount) -> bool:
    return not db.scalar(
        select(
            exists().where(
                ClientAccount.company_id == account.company_id, ClientAccount.id != account.id
            )
        )
    )


def _has_business_relation(db: Session, company: ClientCompany) -> bool:
    return any(
        db.scalar(select(exists().where(model.company_id == company.id)))
        for model in (Invoice, Contract)
    ) or bool(db.scalar(select(exists().where(Project.client_company_id == company.id))))


def _company_file_keys(db: Session, company: ClientCompany) -> list[str]:
    brief_files = (
        select(BriefFile.file_key).join(ProjectBrief).where(ProjectBrief.company_id == company.id)
    )
    message_files = (
        select(ClientMessage.file_key)
        .join(ClientConversation)
        .where(ClientConversation.company_id == company.id)
    )
    keys = [*db.scalars(brief_files), *db.scalars(message_files)]
    return [key for key in keys if key]


def _forget_in_history(db: Session, account: ClientAccount) -> None:
    """Efface l'historique du profil et anonymise les actions sur les projets."""
    db.execute(
        delete(ActivityLog).where(
            ActivityLog.entity_type == "client_account", ActivityLog.entity_id == account.id
        )
    )
    db.execute(
        update(ActivityLog)
        .where(ActivityLog.client_account_id == account.id)
        .values(client_actor_name=DELETED_ACTOR_NAME)
    )
