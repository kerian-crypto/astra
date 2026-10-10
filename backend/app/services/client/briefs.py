"""Cahier des charges client : saisie par écrans dans Astra Client,
validation des réponses, puis transformation en projet par Astra Hub."""

import uuid
from datetime import UTC, date, datetime
from typing import Any, BinaryIO

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.storage import LocalFileStorage
from app.models import BriefFile, ClientAccount, ClientCompany, ProjectBrief, User
from app.models.client_enums import BriefStatus, ClientNotificationKind, ClientPermission
from app.models.enums import NotificationKind
from app.schemas.plan import ProjectPlan
from app.services import activity_service, notification_service, plan_service
from app.services.client import access, audit, conversations, files, notifications
from app.services.client.brief_plan import propose_plan
from app.services.client.brief_questions import FILE_QUESTIONS, QUESTIONS, SECTIONS, Question
from app.services.client.brief_questions import QuestionType as T
from app.services.client.hub_access import require_client_manager
from app.services.errors import ConflictError, NotFoundError, ServiceError

BRIEF_NOT_FOUND = "Cahier des charges introuvable."
MAX_TEXT = 500
MAX_LONG_TEXT = 8_000
MAX_LIST_ITEM = 300
MAX_NUMBER = 10_000_000
EDITABLE = frozenset({BriefStatus.DRAFT})


# ---------- Validation des réponses ----------


def _clean_answer(question: Question, value: Any) -> Any:
    """Normalise une réponse ; lève ServiceError si son type est incorrect.
    `None` ou vide efface la réponse."""
    label = f"« {question.label} »"
    if value is None or value == "" or value == []:
        return None
    match question.type:
        case T.TEXT | T.LONG_TEXT:
            if not isinstance(value, str):
                raise ServiceError(f"Réponse invalide pour {label}.")
            limit = MAX_TEXT if question.type == T.TEXT else MAX_LONG_TEXT
            text = value.strip()
            if len(text) > limit:
                raise ServiceError(f"Réponse trop longue pour {label}.")
            return text or None
        case T.NUMBER:
            if isinstance(value, bool) or not isinstance(value, int | float):
                raise ServiceError(f"Indiquez un nombre pour {label}.")
            if not 0 <= value <= MAX_NUMBER:
                raise ServiceError(f"Nombre hors limites pour {label}.")
            return int(value)
        case T.LIST:
            if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
                raise ServiceError(f"Réponse invalide pour {label}.")
            items = [v.strip() for v in value if v.strip()]
            if any(len(v) > MAX_LIST_ITEM for v in items):
                raise ServiceError(f"Un élément est trop long dans {label}.")
            if question.max_items and len(items) > question.max_items:
                raise ServiceError(f"{question.max_items} éléments maximum pour {label}.")
            return items or None
        case T.SINGLE_CHOICE:
            if value not in {c.value for c in question.choices}:
                raise ServiceError(f"Choix invalide pour {label}.")
            return value
        case T.MULTI_CHOICE:
            if not isinstance(value, dict):
                raise ServiceError(f"Réponse invalide pour {label}.")
            selected = value.get("selected") or []
            other = value.get("other")
            allowed = {c.value for c in question.choices}
            if not isinstance(selected, list) or not set(selected) <= allowed:
                raise ServiceError(f"Choix invalide pour {label}.")
            if other is not None and (not question.allow_other or not isinstance(other, str)):
                raise ServiceError(f"Précision invalide pour {label}.")
            other = (other or "").strip()[:MAX_LIST_ITEM] or None
            count = len(set(selected)) + (1 if other else 0)
            if question.max_items and count > question.max_items:
                raise ServiceError(f"{question.max_items} choix maximum pour {label}.")
            if not count:
                return None
            return {"selected": list(dict.fromkeys(selected)), "other": other}
        case T.DATE:
            try:
                return date.fromisoformat(str(value)).isoformat()
            except ValueError:
                raise ServiceError(f"Date invalide pour {label}.") from None
        case T.FILES:
            raise ServiceError(f"Les fichiers de {label} s'envoient séparément.")
    raise ServiceError(f"Réponse invalide pour {label}.")


def merge_answers(current: dict[str, Any], changes: dict[str, Any]) -> dict[str, Any]:
    merged = dict(current)
    for question_id, value in changes.items():
        question = QUESTIONS.get(question_id)
        if question is None:
            raise ServiceError("Question inconnue.")
        cleaned = _clean_answer(question, value)
        if cleaned is None:
            merged.pop(question_id, None)
        else:
            merged[question_id] = cleaned
    return merged


def missing_required(brief: ProjectBrief) -> list[Question]:
    missing = []
    for question in QUESTIONS.values():
        if not question.required:
            continue
        if question.type == T.FILES:
            if not any(f.question_id == question.id for f in brief.files):
                missing.append(question)
            continue
        answer = brief.answers.get(question.id)
        too_few = (
            question.min_items
            and question.type in (T.LIST,)
            and len(answer or []) < question.min_items
        )
        if answer in (None, "", []) or too_few:
            missing.append(question)
    return missing


def section_progress(brief: ProjectBrief) -> dict[str, tuple[int, int]]:
    """(répondues, total) par section, pour la barre de progression."""
    progress = {}
    for section in SECTIONS:
        answered = sum(
            1
            for q in section.questions
            if (q.type == T.FILES and any(f.question_id == q.id for f in brief.files))
            or brief.answers.get(q.id) not in (None, "", [])
        )
        progress[section.id] = (answered, len(section.questions))
    return progress


def title_of(brief: ProjectBrief) -> str:
    """Titre lisible : premier projet choisi + entreprise."""
    company = (brief.answers.get("company_name") or "").split("\n")[0][:80]
    types = (brief.answers.get("project_types") or {}).get("selected") or []
    labels = {c.value: c.label for c in QUESTIONS["project_types"].choices}
    kind = labels.get(types[0], "Projet") if types else "Projet"
    return f"{kind} — {company}" if company else kind


# ---------- Astra Client ----------


def _client_statement(account: ClientAccount):
    return select(ProjectBrief).where(ProjectBrief.company_id == account.company_id)


def list_for_client(db: Session, account: ClientAccount) -> list[ProjectBrief]:
    access.require(account, ClientPermission.SUBMIT_BRIEF)
    return list(db.scalars(_client_statement(account).order_by(ProjectBrief.created_at.desc())))


def get_for_client(db: Session, account: ClientAccount, brief_id: uuid.UUID) -> ProjectBrief:
    access.require(account, ClientPermission.SUBMIT_BRIEF)
    brief = db.scalar(_client_statement(account).where(ProjectBrief.id == brief_id))
    if brief is None:
        raise NotFoundError(BRIEF_NOT_FOUND)
    return brief


def start(db: Session, account: ClientAccount) -> ProjectBrief:
    """Nouveau brouillon, prérempli avec ce qu'on sait déjà de l'entreprise.
    Un brouillon en cours est repris plutôt que dupliqué."""
    access.require(account, ClientPermission.SUBMIT_BRIEF)
    draft = db.scalar(
        _client_statement(account).where(
            ProjectBrief.status == BriefStatus.DRAFT, ProjectBrief.account_id == account.id
        )
    )
    if draft is not None:
        return draft
    company = account.company
    prefill = {
        "company_name": company.name,
        "whatsapp": company.phone or account.phone,
        "sector": company.sector,
    }
    brief = ProjectBrief(
        company_id=account.company_id,
        account_id=account.id,
        answers={k: v for k, v in prefill.items() if v},
        current_section=SECTIONS[0].id,
    )
    db.add(brief)
    db.commit()
    return brief


def _require_editable(brief: ProjectBrief) -> None:
    if brief.status not in EDITABLE:
        raise ConflictError("Ce cahier des charges a déjà été transmis à Astra.")


def save(
    db: Session,
    account: ClientAccount,
    brief: ProjectBrief,
    *,
    answers: dict[str, Any],
    current_section: str | None,
) -> ProjectBrief:
    """Enregistre les réponses d'un écran (le questionnaire reprend là où
    le client s'est arrêté, même sur un autre téléphone)."""
    _require_editable(brief)
    brief.answers = merge_answers(brief.answers, answers)
    if current_section is not None:
        if current_section not in {s.id for s in SECTIONS}:
            raise ServiceError("Section inconnue.")
        brief.current_section = current_section
    db.commit()
    return brief


def add_file(
    db: Session,
    storage: LocalFileStorage,
    brief: ProjectBrief,
    *,
    question_id: str,
    filename: str,
    source: BinaryIO,
    max_bytes: int,
) -> BriefFile:
    _require_editable(brief)
    if question_id not in FILE_QUESTIONS:
        raise ServiceError("Cette question n'accepte pas de fichier.")
    limit = QUESTIONS[question_id].max_items or 10
    if sum(1 for f in brief.files if f.question_id == question_id) >= limit:
        raise ServiceError(f"{limit} fichiers maximum pour cette question.")
    entry = BriefFile(brief_id=brief.id, question_id=question_id)
    key = files.attach(storage, entry, filename=filename, source=source, max_bytes=max_bytes)
    try:
        db.add(entry)
        db.commit()
    except Exception:
        db.rollback()
        storage.delete(key)
        raise
    db.refresh(brief)
    return entry


def get_file(brief: ProjectBrief, file_id: uuid.UUID) -> BriefFile:
    entry = next((f for f in brief.files if f.id == file_id), None)
    if entry is None:
        raise NotFoundError("Fichier introuvable.")
    return entry


def remove_file(
    db: Session, storage: LocalFileStorage, brief: ProjectBrief, file_id: uuid.UUID
) -> None:
    _require_editable(brief)
    entry = get_file(brief, file_id)
    key = entry.file_key
    brief.files.remove(entry)
    db.commit()
    if key:
        storage.delete(key)


def submit(db: Session, account: ClientAccount, brief: ProjectBrief) -> ProjectBrief:
    _require_editable(brief)
    missing = missing_required(brief)
    if missing:
        names = ", ".join(f"« {q.label} »" for q in missing[:3])
        more = f" et {len(missing) - 3} autre(s)" if len(missing) > 3 else ""
        raise ServiceError(f"Il reste des réponses obligatoires : {names}{more}.")
    brief.status = BriefStatus.SUBMITTED
    brief.submitted_at = datetime.now(UTC)
    audit.record(
        db,
        account,
        entity_type="project_brief",
        entity_id=brief.id,
        action="submitted",
        changes={"title": title_of(brief)},
    )
    notification_service.notify_many(
        db,
        user_ids=conversations.client_managers(db),
        actor=None,
        kind=NotificationKind.CLIENT_BRIEF,
        title=f"Nouveau cahier des charges · {account.company.name}",
        body=title_of(brief),
        entity_type="project_brief",
        entity_id=brief.id,
    )
    db.commit()
    return brief


# ---------- Astra Hub ----------


def list_for_hub(db: Session, user: User, *, status: BriefStatus | None) -> list[ProjectBrief]:
    require_client_manager(user)
    statement = select(ProjectBrief).where(ProjectBrief.status != BriefStatus.DRAFT)
    if status is not None:
        statement = statement.where(ProjectBrief.status == status)
    return list(db.scalars(statement.order_by(ProjectBrief.submitted_at.desc()).limit(200)))


def get_for_hub(db: Session, user: User, brief_id: uuid.UUID) -> ProjectBrief:
    require_client_manager(user)
    brief = db.get(ProjectBrief, brief_id)
    # Les brouillons restent privés tant que le client ne les a pas transmis.
    if brief is None or brief.status == BriefStatus.DRAFT:
        raise NotFoundError(BRIEF_NOT_FOUND)
    return brief


def start_review(db: Session, user: User, brief: ProjectBrief) -> ProjectBrief:
    require_client_manager(user)
    if brief.status == BriefStatus.SUBMITTED:
        brief.status = BriefStatus.IN_REVIEW
        brief.reviewed_by_id = user.id
        db.commit()
    return brief


def plan_for(brief: ProjectBrief, *, today: date | None = None) -> ProjectPlan:
    return propose_plan(brief.answers, title=title_of(brief), today=today or date.today())


def convert(
    db: Session,
    user: User,
    brief: ProjectBrief,
    *,
    plan: ProjectPlan | None,
) -> ProjectBrief:
    """Crée le projet (phases et tâches déduites, éventuellement retouchées
    par le membre) et l'ouvre au client dans son espace."""
    require_client_manager(user)
    if brief.status in (BriefStatus.CONVERTED, BriefStatus.ARCHIVED, BriefStatus.DRAFT):
        raise ConflictError("Ce cahier des charges ne peut plus être transformé en projet.")
    company = db.get(ClientCompany, brief.company_id)
    project = plan_service.build_project_from_plan(db, user, plan or plan_for(brief))
    project.client_company_id = company.id
    project.client_summary = brief.answers.get("project_description")
    brief.status = BriefStatus.CONVERTED
    brief.project_id = project.id
    brief.reviewed_by_id = user.id
    db.flush()
    activity_service.record(
        db,
        actor=user,
        project_id=project.id,
        entity_type="project",
        entity_id=project.id,
        action="linked_to_client",
    )
    notifications.notify_company(
        db,
        company.id,
        ClientPermission.VIEW_PROJECT,
        kind=ClientNotificationKind.PROJECT_ADDED,
        title=f"Votre projet est lancé : {project.name}",
        body="Astra a étudié votre cahier des charges et planifié le projet.",
        entity_type="project",
        entity_id=project.id,
    )
    db.commit()
    return brief


def archive(db: Session, user: User, brief: ProjectBrief) -> ProjectBrief:
    require_client_manager(user)
    if brief.status == BriefStatus.CONVERTED:
        raise ConflictError("Un cahier des charges transformé en projet ne s'archive pas.")
    brief.status = BriefStatus.ARCHIVED
    db.commit()
    return brief
