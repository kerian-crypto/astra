import uuid
from datetime import datetime

from sqlalchemy import Select, or_, select
from sqlalchemy.orm import Session

from app.models import Meeting, MeetingParticipant, Project, User
from app.models.enums import MeetingStatus, NotificationKind, ProjectRole
from app.schemas.meeting import MeetingCreate, MeetingUpdate
from app.services import activity_service, notification_service, permissions, project_service
from app.services.errors import NotFoundError, PermissionDeniedError

MEETING_NOT_FOUND = "Réunion introuvable."
ENTITY = "meeting"


def visible_meeting_ids(user: User) -> Select[tuple[uuid.UUID]]:
    """Réunions visibles : celles des projets visibles, celles que l'on
    organise et celles auxquelles on participe."""
    statement = select(Meeting.id)
    if permissions.is_admin(user):
        return statement
    participations = select(MeetingParticipant.meeting_id).where(
        MeetingParticipant.user_id == user.id
    )
    return statement.where(
        or_(
            Meeting.project_id.in_(permissions.visible_project_ids(user)),
            Meeting.created_by_id == user.id,
            Meeting.id.in_(participations),
        )
    )


def _is_participant(meeting: Meeting, user: User) -> bool:
    return any(p.id == user.id for p in meeting.participants)


def _project_role(db: Session, user: User, meeting: Meeting) -> ProjectRole | None:
    if meeting.project_id is None:
        return None
    project = db.get(Project, meeting.project_id)
    return permissions.get_project_role(db, user, project) if project else None


def can_edit(db: Session, user: User, meeting: Meeting) -> bool:
    """Organisateur, responsable du projet ou administrateur."""
    if permissions.is_admin(user) or meeting.created_by_id == user.id:
        return True
    return _project_role(db, user, meeting) == ProjectRole.LEAD


def get_accessible_meeting(
    db: Session, user: User, meeting_id: uuid.UUID, *, write: bool = False
) -> Meeting:
    meeting = db.get(Meeting, meeting_id)
    if meeting is None:
        raise NotFoundError(MEETING_NOT_FOUND)
    readable = (
        permissions.is_admin(user)
        or meeting.created_by_id == user.id
        or _is_participant(meeting, user)
        or _project_role(db, user, meeting) is not None
    )
    if not readable:
        raise NotFoundError(MEETING_NOT_FOUND)
    if write and not can_edit(db, user, meeting):
        raise PermissionDeniedError("Seuls l'organisateur et le responsable modifient la réunion.")
    return meeting


def list_meetings(
    db: Session,
    user: User,
    *,
    start: datetime | None = None,
    end: datetime | None = None,
    project_id: uuid.UUID | None = None,
    status: MeetingStatus | None = None,
    limit: int = 100,
) -> list[Meeting]:
    statement = select(Meeting).where(Meeting.id.in_(visible_meeting_ids(user)))
    if start is not None:
        statement = statement.where(Meeting.scheduled_at >= start)
    if end is not None:
        statement = statement.where(Meeting.scheduled_at < end)
    if project_id is not None:
        statement = statement.where(Meeting.project_id == project_id)
    if status is not None:
        statement = statement.where(Meeting.status == status)
    return list(db.scalars(statement.order_by(Meeting.scheduled_at).limit(limit)))


def my_upcoming_meetings(db: Session, user: User, start: datetime, end: datetime) -> list[Meeting]:
    """Réunions planifiées où je suis participant ou organisateur."""
    participations = select(MeetingParticipant.meeting_id).where(
        MeetingParticipant.user_id == user.id
    )
    return list(
        db.scalars(
            select(Meeting)
            .where(
                or_(Meeting.created_by_id == user.id, Meeting.id.in_(participations)),
                Meeting.status == MeetingStatus.PLANNED,
                Meeting.scheduled_at >= start,
                Meeting.scheduled_at < end,
            )
            .order_by(Meeting.scheduled_at)
        )
    )


def _load_participants(db: Session, ids: list[uuid.UUID], organizer: User) -> list[User]:
    unique_ids = set(ids) | {organizer.id}
    users = list(db.scalars(select(User).where(User.id.in_(unique_ids), User.is_active.is_(True))))
    if len(users) != len(unique_ids):
        raise NotFoundError("Participant introuvable ou inactif.")
    return users


# Changements qui imposent de prévenir les participants.
_LOGISTICS_FIELDS = {"title", "scheduled_at", "duration_minutes", "location"}
# Cible d'une notification dont la réunion n'existe plus : pas de navigation.
DELETED_ENTITY = "deleted"


def _when(meeting: Meeting) -> str:
    return meeting.scheduled_at.strftime("%d/%m/%Y %H:%M UTC")


def _invite(db: Session, actor: User, meeting: Meeting, invitees: list[User]) -> None:
    notification_service.notify_many(
        db,
        user_ids=[invitee.id for invitee in invitees],
        actor=actor,
        kind=NotificationKind.MEETING_INVITE,
        title=f"{actor.full_name} vous invite : {meeting.title}",
        body=_when(meeting),
        entity_type="meeting",
        entity_id=meeting.id,
    )


def _notify_cancelled(
    db: Session, actor: User, meeting: Meeting, participant_ids: set[uuid.UUID], entity_type: str
) -> None:
    notification_service.notify_many(
        db,
        user_ids=participant_ids,
        actor=actor,
        kind=NotificationKind.MEETING_CANCELLED,
        title=f"Réunion annulée : {meeting.title}",
        body=f"{_when(meeting)} · annulée par {actor.full_name}",
        entity_type=entity_type,
        entity_id=meeting.id,
    )


def _notify_changes(
    db: Session, actor: User, meeting: Meeting, changed: set[str], participant_ids: set[uuid.UUID]
) -> None:
    if "status" in changed and meeting.status == MeetingStatus.CANCELLED:
        _notify_cancelled(db, actor, meeting, participant_ids, "meeting")
        return
    if changed & _LOGISTICS_FIELDS:
        body = _when(meeting) + (f" · {meeting.location}" if meeting.location else "")
        title = f"{actor.full_name} a modifié la réunion : {meeting.title}"
    elif "minutes" in changed and meeting.minutes:
        body, title = None, f"Compte rendu disponible : {meeting.title}"
    else:
        return
    notification_service.notify_many(
        db,
        user_ids=participant_ids,
        actor=actor,
        kind=NotificationKind.MEETING_UPDATED,
        title=title,
        body=body,
        entity_type="meeting",
        entity_id=meeting.id,
    )


def create_meeting(db: Session, user: User, data: MeetingCreate) -> Meeting:
    if data.project_id is not None:
        # Il faut pouvoir contribuer au projet pour y planifier une réunion.
        project_service.get_accessible_project(db, user, data.project_id, ProjectRole.CONTRIBUTOR)
    meeting = Meeting(
        created_by_id=user.id,
        **data.model_dump(exclude={"participant_ids"}),
    )
    meeting.participants = _load_participants(db, data.participant_ids, user)
    db.add(meeting)
    db.flush()
    _invite(db, user, meeting, meeting.participants)
    activity_service.record(
        db,
        actor=user,
        project_id=meeting.project_id,
        entity_type=ENTITY,
        entity_id=meeting.id,
        action="created",
        changes={"title": meeting.title},
    )
    db.commit()
    return meeting


def update_meeting(db: Session, user: User, meeting: Meeting, data: MeetingUpdate) -> Meeting:
    changes = data.model_dump(exclude_unset=True, exclude={"participant_ids"})
    delta = activity_service.diff(meeting, changes)
    previous = {p.id for p in meeting.participants}
    for field, value in changes.items():
        setattr(meeting, field, value)
    if data.participant_ids is not None:
        organizer = db.get(User, meeting.created_by_id)
        meeting.participants = _load_participants(db, data.participant_ids, organizer)
        _invite(db, user, meeting, [p for p in meeting.participants if p.id not in previous])
        delta["participants"] = {"to": len(meeting.participants)}
    # Les nouveaux invités ont déjà reçu l'invitation à jour.
    _notify_changes(db, user, meeting, set(delta), previous & {p.id for p in meeting.participants})
    if delta:
        activity_service.record(
            db,
            actor=user,
            project_id=meeting.project_id,
            entity_type=ENTITY,
            entity_id=meeting.id,
            action="updated",
            changes={k: v for k, v in delta.items() if k not in ("agenda", "minutes")}
            | ({"minutes": "modifié"} if "minutes" in delta else {}),
        )
    db.commit()
    return meeting


def delete_meeting(db: Session, user: User, meeting: Meeting) -> None:
    if meeting.status == MeetingStatus.PLANNED:
        participant_ids = {p.id for p in meeting.participants}
        _notify_cancelled(db, user, meeting, participant_ids, DELETED_ENTITY)
    db.delete(meeting)
    db.commit()
