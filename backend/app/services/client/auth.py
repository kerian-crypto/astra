"""Authentification Astra Client.

Mêmes garanties que pour les membres (`auth_service`) : jetons d'accès
courts, refresh opaques hachés et renouvelés à chaque usage, détection de
réutilisation, limitation des tentatives, aucune énumération des comptes.
Seules l'audience des jetons et la table des comptes diffèrent.
"""

import logging
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import (
    DUMMY_PASSWORD_HASH,
    create_client_access_token,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)
from app.models import ClientAccount, ClientCompany, ClientInvitation, ClientRefreshToken, User
from app.models.client_enums import SELF_REGISTERED_PERMISSIONS, InvitationPurpose
from app.models.enums import NotificationKind
from app.schemas.auth import TokenPair
from app.schemas.client.auth import ClientRegisterRequest, InvitationLink
from app.services import notification_service
from app.services.auth_service import INVALID_CREDENTIALS, INVALID_REFRESH, TOO_MANY_ATTEMPTS
from app.services.client import audit
from app.services.client.conversations import client_managers
from app.services.errors import (
    AuthenticationError,
    ConflictError,
    RateLimitedError,
    ServiceError,
)

logger = logging.getLogger(__name__)

INVALID_INVITATION = "Ce lien n'est plus valide. Demandez-en un nouveau à votre contact Astra."


def is_usable(account: ClientAccount | None) -> bool:
    """Compte activé, actif, et entreprise active."""
    return (
        account is not None
        and account.is_active
        and account.activated_at is not None
        and account.password_hash is not None
        and account.company.is_active
    )


def _issue_tokens(
    db: Session, account: ClientAccount, family_id: uuid.UUID, settings: Settings
) -> TokenPair:
    raw_refresh = generate_refresh_token()
    db.add(
        ClientRefreshToken(
            account_id=account.id,
            family_id=family_id,
            token_hash=hash_refresh_token(raw_refresh),
            expires_at=datetime.now(UTC) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    db.commit()
    return TokenPair(
        access_token=create_client_access_token(account.id, settings),
        refresh_token=raw_refresh,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def login(
    db: Session,
    email: str,
    password: str,
    client_key: str,
    limiter: SlidingWindowRateLimiter,
    settings: Settings,
) -> TokenPair:
    rate_key = f"client:{client_key}:{email}"
    if limiter.is_blocked(rate_key):
        raise RateLimitedError(TOO_MANY_ATTEMPTS)

    account = db.scalar(select(ClientAccount).where(ClientAccount.email == email))
    stored_hash = account.password_hash if account and account.password_hash else None
    password_ok = verify_password(password, stored_hash or DUMMY_PASSWORD_HASH)
    if not (password_ok and stored_hash and is_usable(account)):
        limiter.record_failure(rate_key)
        logger.info("Échec de connexion client (client=%s)", client_key)
        raise AuthenticationError(INVALID_CREDENTIALS)

    limiter.reset(rate_key)
    account.last_login_at = datetime.now(UTC)
    audit.record(db, account, entity_type="client_account", entity_id=account.id, action="login")
    return _issue_tokens(db, account, family_id=uuid.uuid4(), settings=settings)


def _revoke_family(db: Session, family_id: uuid.UUID) -> None:
    db.execute(
        update(ClientRefreshToken)
        .where(ClientRefreshToken.family_id == family_id, ClientRefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    db.commit()


def refresh(db: Session, raw_refresh: str, settings: Settings) -> TokenPair:
    stored = db.scalar(
        select(ClientRefreshToken)
        .where(ClientRefreshToken.token_hash == hash_refresh_token(raw_refresh))
        .with_for_update()
    )
    if stored is None:
        raise AuthenticationError(INVALID_REFRESH)
    if stored.revoked_at is not None:
        logger.warning(
            "Réutilisation d'un refresh token client révoqué (compte=%s)", stored.account_id
        )
        _revoke_family(db, stored.family_id)
        raise AuthenticationError(INVALID_REFRESH)

    account = db.get(ClientAccount, stored.account_id)
    if stored.expires_at <= datetime.now(UTC) or not is_usable(account):
        _revoke_family(db, stored.family_id)
        raise AuthenticationError(INVALID_REFRESH)

    stored.revoked_at = datetime.now(UTC)
    return _issue_tokens(db, account, family_id=stored.family_id, settings=settings)


def logout(db: Session, raw_refresh: str) -> None:
    stored = db.scalar(
        select(ClientRefreshToken).where(
            ClientRefreshToken.token_hash == hash_refresh_token(raw_refresh)
        )
    )
    if stored is None:
        return
    account = db.get(ClientAccount, stored.account_id)
    if account is not None:
        audit.record(
            db, account, entity_type="client_account", entity_id=account.id, action="logout"
        )
    _revoke_family(db, stored.family_id)


def revoke_all_sessions(db: Session, account_id: uuid.UUID) -> None:
    db.execute(
        update(ClientRefreshToken)
        .where(ClientRefreshToken.account_id == account_id, ClientRefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


# ---------- Invitations (liens à usage unique) ----------


def issue_invitation(
    db: Session,
    account: ClientAccount,
    purpose: InvitationPurpose,
    issuer: User,
    settings: Settings,
) -> InvitationLink:
    """Nouveau lien ; les liens précédents encore valides sont annulés.
    Ajoute à la session sans commit. Le jeton brut n'est jamais stocké."""
    now = datetime.now(UTC)
    db.execute(
        update(ClientInvitation)
        .where(ClientInvitation.account_id == account.id, ClientInvitation.used_at.is_(None))
        .values(used_at=now)
    )
    raw_token = generate_refresh_token()
    db.add(
        ClientInvitation(
            account_id=account.id,
            purpose=purpose,
            token_hash=hash_refresh_token(raw_token),
            expires_at=now + timedelta(hours=settings.CLIENT_INVITATION_TTL_HOURS),
            created_by_id=issuer.id,
        )
    )
    return InvitationLink(
        token=raw_token,
        link=f"{settings.CLIENT_APP_LINK_BASE}?token={raw_token}",
        purpose=purpose.value,
        expires_in_hours=settings.CLIENT_INVITATION_TTL_HOURS,
    )


def activate(db: Session, raw_token: str, password: str, settings: Settings) -> TokenPair:
    """Consomme le lien (activation ou nouveau mot de passe) et ouvre une session."""
    invitation = db.scalar(
        select(ClientInvitation)
        .where(ClientInvitation.token_hash == hash_refresh_token(raw_token))
        .with_for_update()
    )
    now = datetime.now(UTC)
    if invitation is None or invitation.used_at is not None or invitation.expires_at <= now:
        raise ServiceError(INVALID_INVITATION)
    account = db.get(ClientAccount, invitation.account_id)
    if account is None or not account.is_active or not account.company.is_active:
        raise ServiceError(INVALID_INVITATION)

    invitation.used_at = now
    account.password_hash = hash_password(password)
    account.activated_at = account.activated_at or now
    account.last_login_at = now
    # Un nouveau mot de passe ferme toutes les sessions ouvertes ailleurs.
    revoke_all_sessions(db, account.id)
    audit.record(
        db,
        account,
        entity_type="client_account",
        entity_id=account.id,
        action="activated"
        if invitation.purpose == InvitationPurpose.ACTIVATION
        else "password_reset",
    )
    return _issue_tokens(db, account, family_id=uuid.uuid4(), settings=settings)


def change_password(
    db: Session, account: ClientAccount, current_password: str, new_password: str
) -> None:
    if not account.password_hash or not verify_password(current_password, account.password_hash):
        raise AuthenticationError("Mot de passe actuel incorrect.")
    account.password_hash = hash_password(new_password)
    revoke_all_sessions(db, account.id)
    audit.record(
        db, account, entity_type="client_account", entity_id=account.id, action="password_changed"
    )
    db.commit()


# ---------- Inscription libre (prospect) ----------

REGISTRATION_REFUSED = (
    "Impossible de créer un compte avec cet email. Connectez-vous, ou demandez un lien "
    "d'accès à votre contact Astra."
)


def register(
    db: Session,
    data: ClientRegisterRequest,
    client_key: str,
    limiter: SlidingWindowRateLimiter,
    settings: Settings,
) -> TokenPair:
    """Crée une entreprise neuve et son premier compte, puis ouvre la session.

    L'isolation reste entière : l'entreprise créée est vide, l'inscription ne
    donne jamais accès aux données d'une entreprise existante (§8, §11).
    Astra est prévenu pour prendre contact avec ce prospect.
    """
    rate_key = f"client-register:{client_key}"
    if limiter.is_blocked(rate_key):
        raise RateLimitedError(TOO_MANY_ATTEMPTS)
    limiter.record_failure(rate_key)
    if db.scalar(select(ClientAccount.id).where(ClientAccount.email == data.email)):
        raise ConflictError(REGISTRATION_REFUSED)

    company = ClientCompany(
        name=data.company_name.strip(),
        email=data.email,
        phone=data.phone,
        address=data.country,
        self_registered=True,
    )
    db.add(company)
    db.flush()
    now = datetime.now(UTC)
    account = ClientAccount(
        company_id=company.id,
        email=data.email,
        full_name=data.full_name,
        phone=data.phone,
        password_hash=hash_password(data.password),
        permissions=[p.value for p in SELF_REGISTERED_PERMISSIONS],
        activated_at=now,
        last_login_at=now,
    )
    account.company = company
    db.add(account)
    db.flush()
    audit.record(
        db, account, entity_type="client_account", entity_id=account.id, action="registered"
    )
    notification_service.notify_many(
        db,
        user_ids=client_managers(db),
        actor=None,
        kind=NotificationKind.CLIENT_SIGNUP,
        title=f"Nouveau prospect : {company.name}",
        body=f"{account.full_name} · {account.email}",
        entity_type="client_company",
        entity_id=company.id,
    )
    return _issue_tokens(db, account, family_id=uuid.uuid4(), settings=settings)
