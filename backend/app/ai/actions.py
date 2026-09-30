"""Actions proposées par Ronda (créer un projet, planifier une réunion…).

« L'IA propose, l'humain décide » : `prepare` transforme la demande comprise
par Ronda en proposition vérifiée, sans rien écrire ; `decide` l'exécute (ou
l'écarte) quand le membre valide, via les services habituels et donc avec ses
droits à lui.
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from pydantic import BaseModel, ValidationError
from sqlalchemy.orm import Session

from app.models import AIConversation, AIMessage, Meeting, Project, Task, User
from app.models.enums import AIActionKind, AIActionStatus, ProjectRole
from app.schemas.ai import AIFocus, DraftAction, ProposedAction, Source
from app.schemas.meeting import DecisionCreate, MeetingCreate
from app.schemas.project import ProjectCreate
from app.schemas.task import TaskCreate
from app.services import (
    decision_service,
    meeting_service,
    permissions,
    project_service,
    task_service,
)
from app.services.errors import ConflictError, NotFoundError

DEFAULT_MEETING_TIME = time(9, 0)
DEFAULT_MEETING_MINUTES = 60


@dataclass(frozen=True)
class Preparation:
    """Proposition prête, ou remarque à ajouter à la réponse de Ronda."""

    action: ProposedAction | None = None
    note: str | None = None


def _parse_date(value: str | None) -> date | None:
    try:
        return date.fromisoformat(value) if value else None
    except ValueError:
        return None


def _parse_time(value: str | None) -> time | None:
    try:
        return time.fromisoformat(value) if value else None
    except ValueError:
        return None


def _project_id(db: Session, kind: str, entity_id: uuid.UUID) -> uuid.UUID | None:
    if kind == "project":
        return entity_id
    if kind in ("work", "task"):
        task = db.get(Task, entity_id)
        return task.project_id if task else None
    if kind == "meeting":
        meeting = db.get(Meeting, entity_id)
        return meeting.project_id if meeting else None
    return None


def _project_for(
    db: Session, draft: DraftAction, sources: list[Source], focus: AIFocus | None
) -> Project | None:
    """Projet désigné par un numéro du contexte, sinon celui de l'écran consulté.

    Les numéros ne renvoient qu'à des éléments déjà visibles par le membre ;
    ses droits sont de toute façon revérifiés à la validation."""
    candidates: list[tuple[str, uuid.UUID]] = []
    source = next((s for s in sources if s.number == draft.project_number), None)
    if source and source.id:
        candidates.append((str(source.type), source.id))
    if focus:
        candidates.append((focus.type.value, focus.id))
    for kind, entity_id in candidates:
        project_id = _project_id(db, kind, entity_id)
        if project_id and (project := db.get(Project, project_id)):
            return project
    return None


def _proposal(
    kind: AIActionKind, title: str, details: list[str], payload: BaseModel | dict
) -> ProposedAction:
    data = payload.model_dump(mode="json") if isinstance(payload, BaseModel) else payload
    return ProposedAction(
        kind=kind,
        status=AIActionStatus.PROPOSED,
        title=title,
        details=[d for d in details if d],
        payload=data,
    )


def _optional(label: str, value: object) -> str:
    return f"{label} : {value}" if value else ""


def _project(user: User, draft: DraftAction) -> Preparation:
    if not permissions.can_create_project(user):
        return Preparation(note="Seuls les managers et administrateurs peuvent créer un projet.")
    due = _parse_date(draft.date)
    data = ProjectCreate(
        name=draft.title.strip(),
        description=draft.description.strip() or None,
        due_date=due,
        **({"priority": draft.priority} if draft.priority else {}),
    )
    details = [
        _optional("Description", data.description),
        _optional("Échéance", due and f"{due:%d/%m/%Y}"),
        f"Priorité : {data.priority}",
    ]
    return Preparation(
        _proposal(AIActionKind.CREATE_PROJECT, f"Créer le projet « {data.name} »", details, data)
    )


def _meeting(draft: DraftAction, project: Project | None, utc_offset_minutes: int) -> Preparation:
    day = _parse_date(draft.date)
    if day is None:
        return Preparation(note="Précisez la date de la réunion pour que je la prépare.")
    local = datetime.combine(day, _parse_time(draft.time) or DEFAULT_MEETING_TIME)
    scheduled_at = (local - timedelta(minutes=utc_offset_minutes)).replace(tzinfo=UTC)
    data = MeetingCreate(
        title=draft.title.strip(),
        project_id=project.id if project else None,
        scheduled_at=scheduled_at,
        duration_minutes=draft.duration_minutes or DEFAULT_MEETING_MINUTES,
        agenda=draft.description.strip() or None,
    )
    details = [
        f"Date : {local:%d/%m/%Y à %H:%M}",
        f"Durée : {data.duration_minutes} min",
        _optional("Projet", project and project.name),
        _optional("Ordre du jour", data.agenda),
    ]
    title = f"Planifier la réunion « {data.title} »"
    return Preparation(_proposal(AIActionKind.SCHEDULE_MEETING, title, details, data))


def _task(draft: DraftAction, project: Project | None) -> Preparation:
    if project is None:
        return Preparation(note="Dites-moi dans quel projet créer cette tâche.")
    due = _parse_date(draft.date)
    data = TaskCreate(
        title=draft.title.strip(),
        description=draft.description.strip() or None,
        due_date=due,
        **({"priority": draft.priority} if draft.priority else {}),
    )
    details = [
        f"Projet : {project.name}",
        _optional("Description", data.description),
        _optional("Échéance", due and f"{due:%d/%m/%Y}"),
        f"Priorité : {data.priority}",
    ]
    payload = {"project_id": str(project.id), "task": data.model_dump(mode="json")}
    title = f"Créer la tâche « {data.title} »"
    return Preparation(_proposal(AIActionKind.CREATE_TASK, title, details, payload))


def _decision(draft: DraftAction, project: Project | None) -> Preparation:
    if project is None:
        return Preparation(note="Dites-moi dans quel projet enregistrer cette décision.")
    data = DecisionCreate(title=draft.title.strip(), description=draft.description.strip() or None)
    details = [f"Projet : {project.name}", _optional("Description", data.description)]
    payload = {"project_id": str(project.id), "decision": data.model_dump(mode="json")}
    title = f"Enregistrer la décision « {data.title} »"
    return Preparation(_proposal(AIActionKind.CREATE_DECISION, title, details, payload))


def prepare(
    db: Session,
    user: User,
    draft: DraftAction,
    sources: list[Source],
    focus: AIFocus | None,
    utc_offset_minutes: int,
) -> Preparation:
    """Aucune écriture : une proposition incomplète ou invalide est abandonnée."""
    if draft.kind == "none":
        return Preparation()
    project = _project_for(db, draft, sources, focus)
    try:
        match draft.kind:
            case "create_project":
                return _project(user, draft)
            case "schedule_meeting":
                return _meeting(draft, project, utc_offset_minutes)
            case "create_task":
                return _task(draft, project)
            case _:
                return _decision(draft, project)
    except ValidationError:
        return Preparation()


# ---------- Validation par le membre ----------


def _execute(db: Session, user: User, action: ProposedAction) -> tuple[str, uuid.UUID]:
    payload = action.payload
    match action.kind:
        case AIActionKind.CREATE_PROJECT:
            project = project_service.create_project(db, user, ProjectCreate(**payload))
            return "project", project.id
        case AIActionKind.SCHEDULE_MEETING:
            meeting = meeting_service.create_meeting(db, user, MeetingCreate(**payload))
            return "meeting", meeting.id
        case AIActionKind.CREATE_TASK:
            project, _ = project_service.get_accessible_project(
                db, user, uuid.UUID(payload["project_id"]), ProjectRole.CONTRIBUTOR
            )
            task = task_service.create_task(db, user, project, TaskCreate(**payload["task"]))
            return "task", task.id
        case AIActionKind.CREATE_DECISION:
            decision = decision_service.create_in_project(
                db, user, uuid.UUID(payload["project_id"]), DecisionCreate(**payload["decision"])
            )
            return "decision", decision.id


def decide(
    db: Session, user: User, conversation_id: uuid.UUID, message_id: uuid.UUID, apply: bool
) -> AIMessage:
    message = db.get(AIMessage, message_id)
    conversation = db.get(AIConversation, conversation_id)
    if (
        message is None
        or conversation is None
        or message.conversation_id != conversation.id
        or conversation.user_id != user.id
    ):
        raise NotFoundError("Message introuvable.")
    if message.action is None:
        raise ConflictError("Ronda n'a proposé aucune action ici.")
    action = ProposedAction.model_validate(message.action)
    if action.status != AIActionStatus.PROPOSED:
        raise ConflictError("Cette action a déjà été traitée.")

    if apply:
        try:
            result_type, result_id = _execute(db, user, action)
        except Exception:
            db.rollback()
            raise
        updated = action.model_copy(
            update={
                "status": AIActionStatus.APPLIED,
                "result_type": result_type,
                "result_id": result_id,
            }
        )
    else:
        updated = action.model_copy(update={"status": AIActionStatus.DISMISSED})
    message.action = updated.model_dump(mode="json")
    db.commit()
    return message
