"""Projets tels que les voit Astra Client, et répercussions côté client des
modifications faites dans Astra Hub (rattachement, statut, avancement)."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    ActivityLog,
    ClientAccount,
    ClientConversation,
    Deliverable,
    Document,
    Project,
    Task,
    User,
)
from app.models.client_enums import (
    ClientNotificationKind,
    ClientPermission,
    ClientProjectStatus,
    ConversationKind,
    DeliverableStatus,
    DocumentVisibility,
)
from app.models.enums import ProjectRole, ProjectStatus, TaskStatus
from app.schemas.client.project import (
    ClientProjectSummary,
    ClientProjectView,
    TeamMemberView,
    TimelineEvent,
)
from app.services import activity_service
from app.services.client import access, notifications
from app.services.client.labels import CLIENT_STATUS_LABELS

_DEFAULT_CLIENT_STATUS = {
    ProjectStatus.IDEA: ClientProjectStatus.PLANNING,
    ProjectStatus.PLANNING: ClientProjectStatus.PLANNING,
    ProjectStatus.ACTIVE: ClientProjectStatus.IN_PROGRESS,
    ProjectStatus.REVIEW: ClientProjectStatus.IN_VALIDATION,
    ProjectStatus.DONE: ClientProjectStatus.DONE,
    ProjectStatus.ARCHIVED: ClientProjectStatus.DONE,
}
FINISHED_STATUSES = frozenset({ClientProjectStatus.DONE, ClientProjectStatus.CANCELLED})


def client_status(project: Project) -> ClientProjectStatus:
    """Statut fixé par Astra Hub, sinon déduit du statut interne (§16)."""
    return project.client_status or _DEFAULT_CLIENT_STATUS[project.status]


def progress(db: Session, project: Project) -> int:
    """Avancement fixé par Astra Hub, sinon part des tâches terminées (§17).
    Les tâches contribuent au calcul sans jamais être exposées."""
    if project.progress is not None:
        return project.progress
    if client_status(project) == ClientProjectStatus.DONE:
        return 100
    total, done = db.execute(
        select(
            func.count(Task.id),
            func.count(Task.id).filter(Task.status == TaskStatus.DONE),
        ).where(Task.project_id == project.id)
    ).one()
    return round(done * 100 / total) if total else 0


def _pending_validations(db: Session, project_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not project_ids:
        return {}
    rows = db.execute(
        select(Deliverable.project_id, func.count())
        .where(
            Deliverable.project_id.in_(project_ids),
            Deliverable.status == DeliverableStatus.AWAITING_VALIDATION,
        )
        .group_by(Deliverable.project_id)
    ).all()
    return dict(rows)


def _summary(db: Session, project: Project, pending: int) -> ClientProjectSummary:
    return ClientProjectSummary(
        id=project.id,
        name=project.name,
        status=client_status(project),
        progress=progress(db, project),
        due_date=project.due_date,
        updated_at=project.updated_at,
        pending_validations=pending,
    )


def list_projects(db: Session, account: ClientAccount) -> list[ClientProjectSummary]:
    access.require(account, ClientPermission.VIEW_PROJECT)
    projects = list(
        db.scalars(access.company_projects_statement(account).order_by(Project.updated_at.desc()))
    )
    pending = _pending_validations(db, [p.id for p in projects])
    return [_summary(db, p, pending.get(p.id, 0)) for p in projects]


def project_conversation(db: Session, project: Project) -> ClientConversation | None:
    return db.scalar(
        select(ClientConversation).where(
            ClientConversation.project_id == project.id,
            ClientConversation.kind == ConversationKind.PROJECT,
        )
    )


def project_view(db: Session, account: ClientAccount, project: Project) -> ClientProjectView:
    pending = _pending_validations(db, [project.id]).get(project.id, 0)
    team = sorted(
        (
            TeamMemberView(
                full_name=m.user.full_name,
                job_title=m.user.job_title,
                is_lead=m.role == ProjectRole.LEAD,
            )
            for m in project.memberships
            if m.user.is_active
        ),
        key=lambda member: (not member.is_lead, member.full_name),
    )
    deliverable_count = db.scalar(
        select(func.count())
        .select_from(Deliverable)
        .where(Deliverable.project_id == project.id, Deliverable.status != DeliverableStatus.DRAFT)
    )
    document_count = db.scalar(
        select(func.count())
        .select_from(Document)
        .where(Document.project_id == project.id, Document.visibility == DocumentVisibility.CLIENT)
    )
    conversation = project_conversation(db, project)
    return ClientProjectView(
        **_summary(db, project, pending).model_dump(),
        description=project.description,
        summary=project.client_summary,
        created_at=project.created_at,
        team=team,
        deliverable_count=deliverable_count,
        document_count=document_count,
        conversation_id=conversation.id if conversation else None,
    )


# Seules ces actions du journal sont montrées au client, avec un libellé
# construit ici : le contenu brut du journal (budget, tâches…) ne sort jamais.
_TIMELINE_ACTIONS = {
    ("deliverable", "version_published"),
    ("deliverable", "approved"),
    ("deliverable", "changes_requested"),
    ("project", "client_status_changed"),
    ("project", "linked_to_client"),
    ("document", "shared_with_client"),
}


def _timeline_label(entry: ActivityLog) -> str:
    changes = entry.changes or {}
    title = changes.get("title", "")
    match (entry.entity_type, entry.action):
        case ("deliverable", "version_published"):
            return f"Livrable « {title} » — version {changes.get('version', '')} publiée"
        case ("deliverable", "approved"):
            return f"Livrable « {title} » approuvé"
        case ("deliverable", "changes_requested"):
            return f"Modification demandée sur « {title} »"
        case ("project", "client_status_changed"):
            status = changes.get("to")
            label = CLIENT_STATUS_LABELS.get(ClientProjectStatus(status)) if status else None
            return f"Statut du projet : {label or 'mis à jour'}"
        case ("project", "linked_to_client"):
            return "Projet ouvert dans votre espace client"
        case ("document", "shared_with_client"):
            return f"Nouveau document : {title}"
    return "Mise à jour du projet"


def timeline(db: Session, project: Project, *, limit: int = 50) -> list[TimelineEvent]:
    entries = db.scalars(
        select(ActivityLog)
        .where(ActivityLog.project_id == project.id)
        .order_by(ActivityLog.created_at.desc())
        .limit(500)
    )
    events = []
    for entry in entries:
        if (entry.entity_type, entry.action) not in _TIMELINE_ACTIONS:
            continue
        events.append(
            TimelineEvent(
                id=entry.id,
                kind=f"{entry.entity_type}.{entry.action}",
                label=_timeline_label(entry),
                # Côté Astra : la marque, pas le nom d'un membre en particulier.
                actor_name=entry.client_actor_name or "Astra",
                entity_id=entry.entity_id,
                created_at=entry.created_at,
            )
        )
        if len(events) >= limit:
            break
    return events


# ---------- Répercussions des modifications faites dans Astra Hub ----------


def after_project_update(
    db: Session, actor: User, project: Project, delta: dict[str, dict]
) -> None:
    """Appelé par `project_service.update_project` avant le commit."""
    if "client_company_id" in delta and project.client_company_id is not None:
        activity_service.record(
            db,
            actor=actor,
            project_id=project.id,
            entity_type="project",
            entity_id=project.id,
            action="linked_to_client",
        )
        notifications.notify_company(
            db,
            project.client_company_id,
            ClientPermission.VIEW_PROJECT,
            kind=ClientNotificationKind.PROJECT_ADDED,
            title=f"Nouveau projet : {project.name}",
            body=project.client_summary or project.description,
            entity_type="project",
            entity_id=project.id,
        )
        return
    visible_change = {"client_status", "status", "progress"} & delta.keys()
    if project.client_company_id is None or not visible_change:
        return
    status_now = client_status(project)
    if "client_status" in delta or "status" in delta:
        activity_service.record(
            db,
            actor=actor,
            project_id=project.id,
            entity_type="project",
            entity_id=project.id,
            action="client_status_changed",
            changes={"to": status_now},
        )
    notifications.notify_company(
        db,
        project.client_company_id,
        ClientPermission.VIEW_PROJECT,
        kind=ClientNotificationKind.PROJECT_UPDATED,
        title=f"Projet « {project.name} » mis à jour",
        body=f"{CLIENT_STATUS_LABELS[status_now]} · {progress(db, project)} %",
        entity_type="project",
        entity_id=project.id,
    )
