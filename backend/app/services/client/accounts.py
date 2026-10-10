"""Administration des entreprises clientes et de leurs comptes (Astra Hub),
et profil du compte connecté (Astra Client)."""

import uuid
from typing import BinaryIO

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.storage import LocalFileStorage
from app.models import ClientAccount, ClientCompany, Project, User
from app.models.client_enums import DEFAULT_CLIENT_PERMISSIONS, ClientPermission, InvitationPurpose
from app.schemas.client.auth import InvitationLink
from app.schemas.client.company import (
    AccountCreate,
    AccountUpdate,
    CompanyClientUpdate,
    CompanyCreate,
    CompanyHub,
    CompanyUpdate,
    MeUpdate,
)
from app.services import activity_service, registration_service
from app.services.client import access, audit
from app.services.client import auth as client_auth
from app.services.client.hub_access import require_client_manager
from app.services.errors import ConflictError, NotFoundError, ServiceError

COMPANY_NOT_FOUND = "Entreprise introuvable."
ACCOUNT_NOT_FOUND = "Compte client introuvable."
EMAIL_TAKEN = "Un compte client utilise déjà cet email."


# ---------- Entreprises (Hub) ----------


def to_hub(db: Session, company: ClientCompany) -> CompanyHub:
    hub = CompanyHub.model_validate(company)
    hub.has_logo = company.logo_key is not None
    hub.account_count = db.scalar(
        select(func.count())
        .select_from(ClientAccount)
        .where(ClientAccount.company_id == company.id)
    )
    hub.project_count = db.scalar(
        select(func.count()).select_from(Project).where(Project.client_company_id == company.id)
    )
    return hub


def list_companies(db: Session, user: User, *, include_inactive: bool) -> list[ClientCompany]:
    require_client_manager(user)
    statement = select(ClientCompany).order_by(ClientCompany.name)
    if not include_inactive:
        statement = statement.where(ClientCompany.is_active.is_(True))
    return list(db.scalars(statement))


def get_company(db: Session, user: User, company_id: uuid.UUID) -> ClientCompany:
    require_client_manager(user)
    company = db.get(ClientCompany, company_id)
    if company is None:
        raise NotFoundError(COMPANY_NOT_FOUND)
    return company


def create_company(db: Session, user: User, data: CompanyCreate) -> ClientCompany:
    require_client_manager(user)
    company = ClientCompany(**data.model_dump(), created_by_id=user.id)
    db.add(company)
    db.flush()
    activity_service.record(
        db,
        actor=user,
        entity_type="client_company",
        entity_id=company.id,
        action="created",
        changes={"name": company.name},
    )
    db.commit()
    return company


def update_company(
    db: Session, user: User, company: ClientCompany, data: CompanyUpdate
) -> ClientCompany:
    require_client_manager(user)
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(company, changes)
    for field, value in changes.items():
        setattr(company, field, value)
    if delta:
        activity_service.record(
            db,
            actor=user,
            entity_type="client_company",
            entity_id=company.id,
            action="updated",
            changes=delta,
        )
    db.commit()
    return company


def set_logo(
    db: Session,
    storage: LocalFileStorage,
    company: ClientCompany,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> ClientCompany:
    """Logo PNG/JPEG, même contrôle que les photos des membres."""
    key = registration_service.store_photo(storage, filename, source, max_bytes)
    previous, company.logo_key = company.logo_key, key
    db.commit()
    if previous:
        storage.delete(previous)
    return company


# ---------- Comptes (Hub) ----------


def get_account(db: Session, user: User, account_id: uuid.UUID) -> ClientAccount:
    require_client_manager(user)
    account = db.get(ClientAccount, account_id)
    if account is None:
        raise NotFoundError(ACCOUNT_NOT_FOUND)
    return account


def list_accounts(db: Session, company: ClientCompany) -> list[ClientAccount]:
    return list(
        db.scalars(
            select(ClientAccount)
            .where(ClientAccount.company_id == company.id)
            .order_by(ClientAccount.full_name)
        )
    )


def create_account(
    db: Session, user: User, company: ClientCompany, data: AccountCreate, settings: Settings
) -> tuple[ClientAccount, InvitationLink]:
    """Crée le compte (inactif tant que le lien n'est pas utilisé) et son lien
    d'activation, renvoyé une seule fois au membre qui le transmet (§8)."""
    require_client_manager(user)
    if not company.is_active:
        raise ServiceError("Cette entreprise est désactivée.")
    permissions = data.permissions if data.permissions is not None else DEFAULT_CLIENT_PERMISSIONS
    account = ClientAccount(
        company_id=company.id,
        email=data.email,
        full_name=data.full_name,
        job_title=data.job_title,
        phone=data.phone,
        permissions=[p.value for p in permissions],
        created_by_id=user.id,
    )
    db.add(account)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError(EMAIL_TAKEN) from exc
    account.company = company
    invitation = client_auth.issue_invitation(
        db, account, InvitationPurpose.ACTIVATION, user, settings
    )
    activity_service.record(
        db,
        actor=user,
        entity_type="client_account",
        entity_id=account.id,
        action="created",
        changes={"email": account.email, "company": company.name},
    )
    db.commit()
    return account, invitation


def update_account(
    db: Session, user: User, account: ClientAccount, data: AccountUpdate
) -> ClientAccount:
    require_client_manager(user)
    changes = data.model_dump(exclude_unset=True)
    if "permissions" in changes:
        changes["permissions"] = [p.value for p in data.permissions or []]
    delta = activity_service.diff(account, changes)
    for field, value in changes.items():
        setattr(account, field, value)
    if changes.get("is_active") is False:
        # Désactivé : plus aucune session, effet immédiat (vérifié à chaque requête).
        client_auth.revoke_all_sessions(db, account.id)
    if delta:
        activity_service.record(
            db,
            actor=user,
            entity_type="client_account",
            entity_id=account.id,
            action="updated",
            changes=delta,
        )
    db.commit()
    return account


def reissue_invitation(
    db: Session, user: User, account: ClientAccount, settings: Settings
) -> InvitationLink:
    """Nouveau lien : activation si le compte n'a jamais été activé, sinon
    nouveau mot de passe (récupération de compte, §9)."""
    require_client_manager(user)
    purpose = (
        InvitationPurpose.ACTIVATION
        if account.activated_at is None
        else InvitationPurpose.PASSWORD_RESET
    )
    link = client_auth.issue_invitation(db, account, purpose, user, settings)
    activity_service.record(
        db,
        actor=user,
        entity_type="client_account",
        entity_id=account.id,
        action="invitation_issued",
        changes={"purpose": purpose},
    )
    db.commit()
    return link


# ---------- Profil (Astra Client) ----------


def update_me(db: Session, account: ClientAccount, data: MeUpdate) -> ClientAccount:
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(account, changes)
    for field, value in changes.items():
        setattr(account, field, value)
    if delta:
        audit.record(
            db,
            account,
            entity_type="client_account",
            entity_id=account.id,
            action="profile_updated",
            changes=delta,
        )
    db.commit()
    return account


def update_own_company(
    db: Session, account: ClientAccount, data: CompanyClientUpdate
) -> ClientCompany:
    access.require(account, ClientPermission.MANAGE_COMPANY_USERS)
    company = account.company
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(company, changes)
    for field, value in changes.items():
        setattr(company, field, value)
    if delta:
        audit.record(
            db,
            account,
            entity_type="client_company",
            entity_id=company.id,
            action="company_updated",
            changes=delta,
        )
    db.commit()
    return company


def list_colleagues(db: Session, account: ClientAccount) -> list[ClientAccount]:
    access.require(account, ClientPermission.MANAGE_COMPANY_USERS)
    return list_accounts(db, account.company)
