import uuid
from datetime import UTC, datetime
from typing import BinaryIO

from sqlalchemy import Select, and_, func, or_, select
from sqlalchemy.orm import Session

from app.core.storage import LocalFileStorage
from app.models import Channel, ChannelMember, Message, Project, ProjectMember, User
from app.models.enums import AccessLevel, ChannelKind, ProjectRole
from app.schemas.chat import ChannelCreate, ChannelPublic, ChannelUpdate
from app.services import permissions, project_service, registration_service
from app.services.errors import ConflictError, NotFoundError, PermissionDeniedError, ServiceError

CHANNEL_NOT_FOUND = "Conversation introuvable."
MEMBERSHIP_KINDS = (ChannelKind.PRIVATE, ChannelKind.DIRECT)


def _member_channel_ids(user: User) -> Select[tuple[uuid.UUID]]:
    return select(ChannelMember.channel_id).where(
        ChannelMember.user_id == user.id, ChannelMember.is_member.is_(True)
    )


def visible_channel_ids(user: User) -> Select[tuple[uuid.UUID]]:
    """Canaux publics, canaux des projets visibles, et canaux privés ou
    directs dont on est membre. Un admin ne lit PAS les conversations privées."""
    return select(Channel.id).where(
        or_(
            Channel.kind == ChannelKind.PUBLIC,
            and_(
                Channel.kind == ChannelKind.PROJECT,
                Channel.project_id.in_(permissions.visible_project_ids(user)),
            ),
            and_(Channel.kind.in_(MEMBERSHIP_KINDS), Channel.id.in_(_member_channel_ids(user))),
        )
    )


def get_accessible_channel(db: Session, user: User, channel_id: uuid.UUID) -> Channel:
    channel = db.scalar(
        select(Channel).where(Channel.id == channel_id, Channel.id.in_(visible_channel_ids(user)))
    )
    if channel is None:
        raise NotFoundError(CHANNEL_NOT_FOUND)
    return channel


def can_post(user: User, channel: Channel) -> bool:
    if channel.is_archived:
        return False
    return not channel.announcements_only or user.access_level in (
        AccessLevel.MANAGER,
        AccessLevel.ADMIN,
    )


def require_can_post(user: User, channel: Channel) -> None:
    if not can_post(user, channel):
        raise PermissionDeniedError("Vous ne pouvez pas publier dans ce canal.")


def can_manage(db: Session, user: User, channel: Channel) -> bool:
    match channel.kind:
        case ChannelKind.PUBLIC:
            return permissions.is_admin(user) or channel.created_by_id == user.id
        case ChannelKind.PRIVATE:
            return channel.created_by_id == user.id
        case ChannelKind.PROJECT:
            project = db.get(Project, channel.project_id)
            return permissions.get_project_role(db, user, project) == ProjectRole.LEAD
        case _:
            return False


def recipients(db: Session, channel: Channel) -> set[uuid.UUID]:
    """Utilisateurs ayant accès au canal (destinataires du temps réel, mentions)."""
    if channel.kind == ChannelKind.PUBLIC:
        statement = select(User.id).where(User.is_active.is_(True))
    elif channel.kind == ChannelKind.PROJECT:
        statement = select(User.id).where(
            User.is_active.is_(True),
            or_(
                User.access_level == AccessLevel.ADMIN,
                User.id.in_(
                    select(ProjectMember.user_id).where(
                        ProjectMember.project_id == channel.project_id
                    )
                ),
            ),
        )
    else:
        statement = select(ChannelMember.user_id).where(
            ChannelMember.channel_id == channel.id, ChannelMember.is_member.is_(True)
        )
    return set(db.scalars(statement))


def members(db: Session, channel: Channel) -> list[User]:
    if channel.kind not in MEMBERSHIP_KINDS:
        return []
    return list(
        db.scalars(
            select(User)
            .join(ChannelMember, ChannelMember.user_id == User.id)
            .where(ChannelMember.channel_id == channel.id, ChannelMember.is_member.is_(True))
            .order_by(User.full_name)
        )
    )


# ---------- Présentation ----------


def _other_member(db: Session, user: User, channel: Channel) -> User | None:
    return next((m for m in members(db, channel) if m.id != user.id), None)


def display_name(db: Session, user: User, channel: Channel) -> str:
    if channel.kind != ChannelKind.DIRECT:
        return channel.name or ""
    other = _other_member(db, user, channel)
    return other.full_name if other else "Conversation"


def photo_url(db: Session, user: User, channel: Channel) -> str | None:
    """URL versionnée (mise en cache côté client) ; photo de l'autre membre
    pour une conversation directe."""
    if channel.kind == ChannelKind.DIRECT:
        other = _other_member(db, user, channel)
        return other.public_photo_url if other else None
    if channel.photo_key:
        return f"channels/{channel.id}/photo?v={channel.photo_key[:8]}"
    return None


def to_public(db: Session, user: User, channels: list[Channel]) -> list[ChannelPublic]:
    """Ajoute nom affiché, non-lus et dernière activité (une requête pour tous)."""
    ids = [c.id for c in channels]
    last_read = (
        select(ChannelMember.channel_id, ChannelMember.last_read_at)
        .where(ChannelMember.user_id == user.id)
        .subquery()
    )
    stats = {
        row.channel_id: row
        for row in db.execute(
            select(
                Message.channel_id,
                func.max(Message.created_at).label("last_at"),
                func.count()
                .filter(
                    Message.author_id != user.id,
                    Message.deleted_at.is_(None),
                    or_(
                        last_read.c.last_read_at.is_(None),
                        Message.created_at > last_read.c.last_read_at,
                    ),
                )
                .label("unread"),
            )
            .outerjoin(last_read, last_read.c.channel_id == Message.channel_id)
            .where(Message.channel_id.in_(ids))
            .group_by(Message.channel_id)
        )
    }
    result = []
    for channel in channels:
        row = stats.get(channel.id)
        public = ChannelPublic.model_validate(channel)
        public.display_name = display_name(db, user, channel)
        public.unread_count = row.unread if row else 0
        public.last_message_at = row.last_at if row else None
        public.can_post = can_post(user, channel)
        public.photo_url = photo_url(db, user, channel)
        public.can_manage = can_manage(db, user, channel)
        result.append(public)
    return result


def list_channels(db: Session, user: User, *, include_archived: bool) -> list[ChannelPublic]:
    statement = select(Channel).where(Channel.id.in_(visible_channel_ids(user)))
    if not include_archived:
        statement = statement.where(Channel.is_archived.is_(False))
    channels = list(db.scalars(statement))
    public = to_public(db, user, channels)
    epoch = datetime.min.replace(tzinfo=UTC)
    return sorted(public, key=lambda c: c.last_message_at or epoch, reverse=True)


# ---------- Création et gestion ----------


def _active_users(db: Session, ids: set[uuid.UUID]) -> list[User]:
    users = list(db.scalars(select(User).where(User.id.in_(ids), User.is_active.is_(True))))
    if len(users) != len(ids):
        raise NotFoundError("Membre introuvable ou inactif.")
    return users


def create_channel(db: Session, user: User, data: ChannelCreate) -> Channel:
    if data.kind == ChannelKind.PUBLIC and not permissions.can_create_project(user):
        raise PermissionDeniedError("Seuls les managers et administrateurs créent des canaux.")
    if data.announcements_only and not permissions.is_admin(user):
        raise PermissionDeniedError("Seuls les administrateurs créent un canal d'annonces.")
    channel = Channel(created_by_id=user.id, **data.model_dump(exclude={"member_ids"}))
    db.add(channel)
    db.flush()
    if data.kind == ChannelKind.PRIVATE:
        for member in _active_users(db, set(data.member_ids) | {user.id}):
            db.add(ChannelMember(channel_id=channel.id, user_id=member.id))
    db.commit()
    return channel


def get_or_create_direct(db: Session, user: User, other_id: uuid.UUID) -> Channel:
    if other_id == user.id:
        raise ServiceError("Impossible d'ouvrir une conversation avec soi-même.")
    (other,) = _active_users(db, {other_id})
    key = ":".join(sorted((str(user.id), str(other.id))))
    channel = db.scalar(select(Channel).where(Channel.direct_key == key))
    if channel is not None:
        return channel
    channel = Channel(kind=ChannelKind.DIRECT, direct_key=key, created_by_id=user.id)
    db.add(channel)
    db.flush()
    db.add_all(
        [
            ChannelMember(channel_id=channel.id, user_id=user.id),
            ChannelMember(channel_id=channel.id, user_id=other.id),
        ]
    )
    db.commit()
    return channel


def get_or_create_project_channel(db: Session, user: User, project_id: uuid.UUID) -> Channel:
    """Chaque projet a automatiquement son espace de discussion (spec §5)."""
    project, _ = project_service.get_accessible_project(db, user, project_id, ProjectRole.VIEWER)
    channel = db.scalar(select(Channel).where(Channel.project_id == project.id))
    if channel is None:
        channel = Channel(kind=ChannelKind.PROJECT, project_id=project.id, name=project.name)
        db.add(channel)
        db.commit()
    return channel


def update_channel(db: Session, user: User, channel: Channel, data: ChannelUpdate) -> Channel:
    if not can_manage(db, user, channel):
        raise PermissionDeniedError("Vous ne pouvez pas modifier ce canal.")
    changes = data.model_dump(exclude_unset=True)
    if changes.get("announcements_only") and not permissions.is_admin(user):
        raise PermissionDeniedError("Seuls les administrateurs créent un canal d'annonces.")
    for field, value in changes.items():
        setattr(channel, field, value)
    db.commit()
    return channel


def set_photo(
    db: Session,
    storage: LocalFileStorage,
    user: User,
    channel: Channel,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> Channel:
    if not can_manage(db, user, channel):
        raise PermissionDeniedError("Vous ne pouvez pas modifier ce canal.")
    previous = channel.photo_key
    channel.photo_key = registration_service.store_photo(storage, filename, source, max_bytes)
    db.commit()
    if previous:
        storage.delete(previous)
    return channel


def remove_photo(db: Session, storage: LocalFileStorage, user: User, channel: Channel) -> Channel:
    if not can_manage(db, user, channel):
        raise PermissionDeniedError("Vous ne pouvez pas modifier ce canal.")
    previous, channel.photo_key = channel.photo_key, None
    db.commit()
    if previous:
        storage.delete(previous)
    return channel


def _membership(db: Session, channel_id: uuid.UUID, user_id: uuid.UUID) -> ChannelMember | None:
    return db.get(ChannelMember, {"channel_id": channel_id, "user_id": user_id})


def add_member(db: Session, user: User, channel: Channel, member_id: uuid.UUID) -> None:
    if channel.kind != ChannelKind.PRIVATE or not can_manage(db, user, channel):
        raise PermissionDeniedError("Vous ne pouvez pas ajouter de membre à ce canal.")
    _active_users(db, {member_id})
    membership = _membership(db, channel.id, member_id)
    if membership is None:
        db.add(ChannelMember(channel_id=channel.id, user_id=member_id))
    else:
        membership.is_member = True
    db.commit()


def remove_member(db: Session, user: User, channel: Channel, member_id: uuid.UUID) -> None:
    """Le gestionnaire retire un membre ; chacun peut quitter un groupe privé."""
    leaving = member_id == user.id
    if channel.kind != ChannelKind.PRIVATE or not (leaving or can_manage(db, user, channel)):
        raise PermissionDeniedError("Vous ne pouvez pas retirer ce membre.")
    membership = _membership(db, channel.id, member_id)
    if membership is None or not membership.is_member:
        raise NotFoundError("Ce membre ne fait pas partie du canal.")
    if leaving and channel.created_by_id == user.id:
        raise ConflictError("Le créateur du groupe ne peut pas le quitter ; archivez-le.")
    membership.is_member = False
    db.commit()


def mark_read(db: Session, user: User, channel: Channel) -> None:
    membership = _membership(db, channel.id, user.id)
    now = datetime.now(UTC)
    if membership is None:
        db.add(
            ChannelMember(channel_id=channel.id, user_id=user.id, is_member=False, last_read_at=now)
        )
    else:
        membership.last_read_at = now
    db.commit()
