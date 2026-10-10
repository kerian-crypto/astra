"""Messagerie entre une entreprise cliente et Astra (§24).

Un message est écrit soit par un compte client (Astra Client), soit par un
membre d'Astra (Astra Hub). Chaque côté est notifié des messages de l'autre.
"""

import uuid
from datetime import UTC, datetime
from typing import BinaryIO

from sqlalchemy import Select, func, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.storage import LocalFileStorage
from app.models import (
    ClientAccount,
    ClientCompany,
    ClientConversation,
    ClientConversationRead,
    ClientMessage,
    Project,
    ProjectMember,
    SupportTicket,
    User,
)
from app.models.client_enums import ClientNotificationKind, ClientPermission, ConversationKind
from app.models.enums import AccessLevel, NotificationKind, ProjectRole
from app.realtime.hub import client_hub, publish_from_thread
from app.schemas.client.common import attached_file
from app.schemas.client.conversation import ConversationHub, ConversationView, MessageView
from app.services import notification_service, permissions
from app.services.client import access, files, notifications
from app.services.client.hub_access import can_manage_clients, require_conversation
from app.services.errors import NotFoundError, PermissionDeniedError, ServiceError

CONVERSATION_NOT_FOUND = "Conversation introuvable."
MAX_BODY_LENGTH = 10_000


# ---------- Représentations ----------


def message_view(message: ClientMessage, reader_id: uuid.UUID) -> MessageView:
    return MessageView(
        id=message.id,
        conversation_id=message.conversation_id,
        author_name=message.author_name,
        from_astra=message.from_astra,
        is_mine=reader_id in (message.author_user_id, message.author_account_id),
        body=message.body,
        file=attached_file(message),
        created_at=message.created_at,
    )


def _last_message(db: Session, conversation_id: uuid.UUID) -> ClientMessage | None:
    return db.scalar(
        select(ClientMessage)
        .where(ClientMessage.conversation_id == conversation_id)
        .order_by(ClientMessage.created_at.desc())
        .limit(1)
    )


def unread_count(db: Session, conversation_id: uuid.UUID, reader_id: uuid.UUID) -> int:
    last_read = select(ClientConversationRead.last_read_at).where(
        ClientConversationRead.conversation_id == conversation_id,
        ClientConversationRead.reader_id == reader_id,
    )
    return db.scalar(
        select(func.count())
        .select_from(ClientMessage)
        .where(
            ClientMessage.conversation_id == conversation_id,
            or_(ClientMessage.author_user_id.is_(None), ClientMessage.author_user_id != reader_id),
            or_(
                ClientMessage.author_account_id.is_(None),
                ClientMessage.author_account_id != reader_id,
            ),
            or_(
                ~last_read.exists(),
                ClientMessage.created_at > last_read.scalar_subquery(),
            ),
        )
    )


def conversation_view(
    db: Session, conversation: ClientConversation, reader_id: uuid.UUID
) -> ConversationView:
    last = _last_message(db, conversation.id)
    project = db.get(Project, conversation.project_id) if conversation.project_id else None
    return ConversationView(
        id=conversation.id,
        kind=conversation.kind,
        subject=conversation.subject,
        project_id=conversation.project_id,
        project_name=project.name if project else None,
        deliverable_id=conversation.deliverable_id,
        ticket_id=conversation.ticket_id,
        last_message=message_view(last, reader_id) if last else None,
        last_message_at=conversation.last_message_at,
        unread_count=unread_count(db, conversation.id, reader_id),
        created_at=conversation.created_at,
    )


def conversation_hub(db: Session, conversation: ClientConversation, user: User) -> ConversationHub:
    company = db.get(ClientCompany, conversation.company_id)
    return ConversationHub(
        **conversation_view(db, conversation, user.id).model_dump(),
        company_id=conversation.company_id,
        company_name=company.name,
    )


def _ordered(statement: Select) -> Select:
    return statement.order_by(
        func.coalesce(ClientConversation.last_message_at, ClientConversation.created_at).desc()
    )


# ---------- Astra Client ----------


def visible_statement(account: ClientAccount) -> Select[tuple[ClientConversation]]:
    statement = select(ClientConversation).where(
        ClientConversation.company_id == account.company_id
    )
    if not account.has_permission(ClientPermission.VIEW_PROJECT):
        statement = statement.where(ClientConversation.kind != ConversationKind.PROJECT)
    if not account.has_permission(ClientPermission.CREATE_TICKET):
        statement = statement.where(ClientConversation.kind != ConversationKind.TICKET)
    return statement


def list_for_client(db: Session, account: ClientAccount) -> list[ClientConversation]:
    return list(db.scalars(_ordered(visible_statement(account))))


def get_for_client(
    db: Session, account: ClientAccount, conversation_id: uuid.UUID
) -> ClientConversation:
    conversation = db.scalar(
        visible_statement(account).where(ClientConversation.id == conversation_id)
    )
    if conversation is None:
        raise NotFoundError(CONVERSATION_NOT_FOUND)
    return conversation


def total_unread_for_client(db: Session, account: ClientAccount) -> int:
    return sum(unread_count(db, c.id, account.id) for c in list_for_client(db, account))


def _can_post_as_client(account: ClientAccount, conversation: ClientConversation) -> bool:
    if conversation.kind == ConversationKind.TICKET:
        return account.has_permission(ClientPermission.CREATE_TICKET)
    return account.has_permission(ClientPermission.SEND_MESSAGE)


def start_for_client(
    db: Session,
    account: ClientAccount,
    *,
    subject: str,
    project_id: uuid.UUID | None,
    body: str,
) -> ClientConversation:
    access.require(account, ClientPermission.SEND_MESSAGE)
    if project_id is not None:
        access.get_project(db, account, project_id)
    conversation = ClientConversation(
        company_id=account.company_id,
        kind=ConversationKind.PROJECT if project_id else ConversationKind.GENERAL,
        subject=subject.strip(),
        project_id=project_id,
    )
    db.add(conversation)
    db.flush()
    _add_message(db, conversation, body=body, account=account)
    db.commit()
    return conversation


def project_conversation_for_client(
    db: Session, account: ClientAccount, project_id: uuid.UUID
) -> ClientConversation:
    """Conversation du projet, créée à la première ouverture."""
    project = access.get_project(db, account, project_id)
    conversation = db.scalar(
        select(ClientConversation)
        .where(
            ClientConversation.project_id == project.id,
            ClientConversation.kind == ConversationKind.PROJECT,
        )
        .order_by(ClientConversation.created_at)
        .limit(1)
    )
    if conversation is None:
        access.require(account, ClientPermission.SEND_MESSAGE)
        conversation = ClientConversation(
            company_id=account.company_id,
            kind=ConversationKind.PROJECT,
            subject=project.name,
            project_id=project.id,
        )
        db.add(conversation)
        db.commit()
    return conversation


# ---------- Astra Hub ----------


def hub_statement(db: Session, user: User) -> Select[tuple[ClientConversation]]:
    statement = select(ClientConversation)
    if can_manage_clients(user):
        return statement
    member_projects = select(ProjectMember.project_id).where(ProjectMember.user_id == user.id)
    assigned_tickets = select(SupportTicket.id).where(SupportTicket.assignee_id == user.id)
    return statement.where(
        or_(
            ClientConversation.project_id.in_(member_projects),
            ClientConversation.ticket_id.in_(assigned_tickets),
        )
    )


def list_for_hub(
    db: Session, user: User, *, company_id: uuid.UUID | None, project_id: uuid.UUID | None
) -> list[ClientConversation]:
    statement = hub_statement(db, user)
    if company_id is not None:
        statement = statement.where(ClientConversation.company_id == company_id)
    if project_id is not None:
        statement = statement.where(ClientConversation.project_id == project_id)
    return list(db.scalars(_ordered(statement).limit(200)))


def get_for_hub(db: Session, user: User, conversation_id: uuid.UUID) -> ClientConversation:
    return require_conversation(db, user, db.get(ClientConversation, conversation_id))


def start_for_hub(
    db: Session,
    user: User,
    *,
    company_id: uuid.UUID,
    subject: str,
    project_id: uuid.UUID | None,
    body: str,
) -> ClientConversation:
    company = db.get(ClientCompany, company_id)
    if company is None or not company.is_active:
        raise NotFoundError("Entreprise introuvable.")
    if project_id is not None:
        project = db.get(Project, project_id)
        if project is None or project.client_company_id != company_id:
            raise NotFoundError("Projet introuvable pour cette entreprise.")
        if not can_manage_clients(user) and permissions.get_project_role(db, user, project) is None:
            raise NotFoundError("Projet introuvable pour cette entreprise.")
    elif not can_manage_clients(user):
        raise PermissionDeniedError("Réservé aux managers et administrateurs.")
    conversation = ClientConversation(
        company_id=company_id,
        kind=ConversationKind.PROJECT if project_id else ConversationKind.GENERAL,
        subject=subject.strip(),
        project_id=project_id,
    )
    db.add(conversation)
    db.flush()
    _add_message(db, conversation, body=body, user=user)
    db.commit()
    return conversation


# ---------- Messages (les deux côtés) ----------


def list_messages(
    db: Session,
    conversation: ClientConversation,
    *,
    before: datetime | None,
    limit: int,
) -> list[ClientMessage]:
    statement = select(ClientMessage).where(ClientMessage.conversation_id == conversation.id)
    if before is not None:
        statement = statement.where(ClientMessage.created_at < before)
    rows = list(db.scalars(statement.order_by(ClientMessage.created_at.desc()).limit(limit)))
    return list(reversed(rows))


def get_message(
    db: Session, conversation: ClientConversation, message_id: uuid.UUID
) -> ClientMessage:
    message = db.get(ClientMessage, message_id)
    if message is None or message.conversation_id != conversation.id:
        raise NotFoundError("Message introuvable.")
    return message


def post_message(
    db: Session,
    storage: LocalFileStorage,
    conversation: ClientConversation,
    *,
    body: str,
    upload: tuple[str, BinaryIO] | None,
    max_bytes: int,
    account: ClientAccount | None = None,
    user: User | None = None,
) -> ClientMessage:
    if account is not None and not _can_post_as_client(account, conversation):
        raise PermissionDeniedError(access.MISSING_PERMISSION)
    message = _add_message(
        db,
        conversation,
        body=body,
        account=account,
        user=user,
        storage=storage,
        upload=upload,
        max_bytes=max_bytes,
    )
    try:
        db.commit()
    except Exception:
        db.rollback()
        if message.file_key:
            storage.delete(message.file_key)
        raise
    _publish(db, conversation, message)
    return message


def _add_message(
    db: Session,
    conversation: ClientConversation,
    *,
    body: str,
    account: ClientAccount | None = None,
    user: User | None = None,
    storage: LocalFileStorage | None = None,
    upload: tuple[str, BinaryIO] | None = None,
    max_bytes: int = 0,
) -> ClientMessage:
    text = (body or "").strip()
    if not text and upload is None:
        raise ServiceError("Le message est vide.")
    if len(text) > MAX_BODY_LENGTH:
        raise ServiceError("Message trop long.")
    message = ClientMessage(
        conversation_id=conversation.id,
        author_account_id=account.id if account else None,
        author_user_id=user.id if user else None,
        author_name=account.full_name if account else user.full_name,  # type: ignore[union-attr]
        body=text,
    )
    if upload is not None and storage is not None:
        filename, source = upload
        files.attach(
            storage,
            message,
            filename=filename,
            source=source,
            max_bytes=max_bytes,
            allow_media=True,
        )
    db.add(message)
    conversation.last_message_at = datetime.now(UTC)
    db.flush()
    _mark_read(db, conversation.id, account.id if account else user.id)  # type: ignore[union-attr]
    if account is not None:
        _notify_astra(db, conversation, account, text)
    else:
        _notify_client(db, conversation, user, text)  # type: ignore[arg-type]
    return message


def _hub_recipients(db: Session, conversation: ClientConversation) -> list[uuid.UUID]:
    """Membres d'Astra à prévenir d'un message client : responsables du
    projet, assigné du ticket, sinon managers et administrateurs."""
    if conversation.project_id is not None:
        leads = list(
            db.scalars(
                select(ProjectMember.user_id).where(
                    ProjectMember.project_id == conversation.project_id,
                    ProjectMember.role == ProjectRole.LEAD,
                )
            )
        )
        if leads:
            return leads
    if conversation.ticket_id is not None:
        ticket = db.get(SupportTicket, conversation.ticket_id)
        if ticket is not None and ticket.assignee_id is not None:
            return [ticket.assignee_id]
    return client_managers(db)


def client_managers(db: Session) -> list[uuid.UUID]:
    return list(
        db.scalars(
            select(User.id).where(
                User.is_active.is_(True),
                User.access_level.in_((AccessLevel.MANAGER, AccessLevel.ADMIN)),
            )
        )
    )


def _notify_astra(
    db: Session, conversation: ClientConversation, account: ClientAccount, text: str
) -> None:
    notification_service.notify_many(
        db,
        user_ids=_hub_recipients(db, conversation),
        actor=None,
        kind=NotificationKind.CLIENT_MESSAGE,
        title=f"{account.full_name} ({account.company.name}) · {conversation.subject}",
        body=text or "Pièce jointe",
        entity_type="client_conversation",
        entity_id=conversation.id,
    )


def _notify_client(db: Session, conversation: ClientConversation, user: User, text: str) -> None:
    permission = (
        ClientPermission.CREATE_TICKET
        if conversation.kind == ConversationKind.TICKET
        else ClientPermission.SEND_MESSAGE
    )
    notifications.notify_company(
        db,
        conversation.company_id,
        permission,
        kind=ClientNotificationKind.NEW_MESSAGE,
        title=f"Astra · {conversation.subject}",
        body=f"{user.full_name} : {text or 'Pièce jointe'}",
        entity_type="client_conversation",
        entity_id=conversation.id,
    )


def _publish(db: Session, conversation: ClientConversation, message: ClientMessage) -> None:
    """Temps réel : les comptes de l'entreprise et les membres concernés."""
    accounts = set(access.recipients(db, conversation.company_id))
    for account_id in accounts:
        publish_from_thread(
            {
                "type": "message.created",
                "message": message_view(message, account_id).model_dump(mode="json"),
            },
            {account_id},
            target=client_hub,
        )
    members = set(_hub_recipients(db, conversation)) | (
        {message.author_user_id} if message.author_user_id else set()
    )
    for user_id in members:
        publish_from_thread(
            {
                "type": "client_message.created",
                "message": message_view(message, user_id).model_dump(mode="json"),
            },
            {user_id},
        )


def _mark_read(db: Session, conversation_id: uuid.UUID, reader_id: uuid.UUID) -> None:
    now = datetime.now(UTC)
    db.execute(
        insert(ClientConversationRead)
        .values(conversation_id=conversation_id, reader_id=reader_id, last_read_at=now)
        .on_conflict_do_update(
            index_elements=["conversation_id", "reader_id"], set_={"last_read_at": now}
        )
    )


def mark_read(db: Session, conversation: ClientConversation, reader_id: uuid.UUID) -> None:
    _mark_read(db, conversation.id, reader_id)
    db.commit()
