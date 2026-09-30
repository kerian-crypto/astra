import uuid
from collections.abc import Iterable

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Project, ProjectMember, User
from app.models.enums import NotificationKind, ProjectRole, ProjectStatus
from app.schemas.project import ProjectCreate, ProjectUpdate
from app.services import activity_service, notification_service, permissions
from app.services.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.services.labels import PROJECT_STATUS_LABELS

# Volontairement identique pour « inexistant » et « non autorisé » :
# un membre ne doit pas pouvoir deviner l'existence d'un projet confidentiel.
PROJECT_NOT_FOUND = "Projet introuvable."
LAST_LEAD = "Le projet doit conserver au moins un responsable."


def list_projects(
    db: Session,
    user: User,
    *,
    status: ProjectStatus | None,
    limit: int,
    offset: int,
) -> list[Project]:
    statement = permissions.visible_projects_statement(user)
    if status is not None:
        statement = statement.where(Project.status == status)
    statement = statement.order_by(Project.updated_at.desc()).limit(limit).offset(offset)
    return list(db.scalars(statement))


def get_accessible_project(
    db: Session, user: User, project_id: uuid.UUID, minimum: ProjectRole
) -> tuple[Project, ProjectRole]:
    """Charge un projet et vérifie le rôle minimal requis.

    Sans aucun accès -> 404. Accès en lecture mais rôle insuffisant -> 403.
    """
    project = db.get(Project, project_id)
    role = permissions.get_project_role(db, user, project) if project else None
    if project is None or role is None:
        raise NotFoundError(PROJECT_NOT_FOUND)
    if not permissions.has_project_role(role, minimum):
        raise PermissionDeniedError("Droits insuffisants sur ce projet.")
    return project, role


def _get_active_user(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise NotFoundError("Membre introuvable.")
    return user


def create_project(db: Session, creator: User, data: ProjectCreate) -> Project:
    project = build_project(db, creator, data)
    db.commit()
    return project


def build_project(db: Session, creator: User, data: ProjectCreate) -> Project:
    """Crée le projet et ses premiers membres dans la session, sans commit."""
    if not permissions.can_create_project(creator):
        raise PermissionDeniedError("Seuls les managers et administrateurs créent des projets.")

    lead = _get_active_user(db, data.lead_id) if data.lead_id else creator
    project = Project(
        **data.model_dump(exclude={"lead_id"}),
        created_by_id=creator.id,
    )
    members = {lead.id: ProjectRole.LEAD}
    if creator.id != lead.id:
        members[creator.id] = ProjectRole.CONTRIBUTOR
    project.memberships = [
        ProjectMember(user_id=user_id, role=role) for user_id, role in members.items()
    ]
    db.add(project)
    db.flush()
    _record(db, creator, project.id, "created", {"name": project.name})
    notify_added_members(db, creator, project, members)
    return project


def notify_added_members(
    db: Session, actor: User, project: Project, user_ids: Iterable[uuid.UUID]
) -> None:
    notification_service.notify_many(
        db,
        user_ids=user_ids,
        actor=actor,
        kind=NotificationKind.PROJECT_ADDED,
        title=f"{actor.full_name} vous a ajouté au projet « {project.name} »",
        body=project.description,
        entity_type="project",
        entity_id=project.id,
    )


def member_ids(project: Project) -> list[uuid.UUID]:
    return [membership.user_id for membership in project.memberships]


def _record(
    db: Session, actor: User, project_id: uuid.UUID, action: str, changes: dict | None = None
) -> None:
    activity_service.record(
        db,
        actor=actor,
        project_id=project_id,
        entity_type="project",
        entity_id=project_id,
        action=action,
        changes=changes,
    )


def update_project(db: Session, actor: User, project: Project, data: ProjectUpdate) -> Project:
    changes = data.model_dump(exclude_unset=True)
    delta = activity_service.diff(project, changes)
    for field, value in changes.items():
        setattr(project, field, value)
    if delta:
        _record(db, actor, project.id, "updated", delta)
    if "status" in delta:
        notification_service.notify_many(
            db,
            user_ids=member_ids(project),
            actor=actor,
            kind=NotificationKind.PROJECT_STATUS,
            title=f"Projet « {project.name} » : {PROJECT_STATUS_LABELS[project.status]}",
            body=f"Statut modifié par {actor.full_name}",
            entity_type="project",
            entity_id=project.id,
        )
    db.commit()
    return project


def delete_project(db: Session, project: Project) -> None:
    db.delete(project)
    db.commit()


def _count_leads(db: Session, project_id: uuid.UUID) -> int:
    """Verrouille la ligne du projet jusqu'au commit : les changements de
    responsables d'un même projet sont sérialisés."""
    db.execute(select(Project.id).where(Project.id == project_id).with_for_update())
    return db.scalar(
        select(func.count())
        .select_from(ProjectMember)
        .where(ProjectMember.project_id == project_id, ProjectMember.role == ProjectRole.LEAD)
    )


def _get_membership(db: Session, project_id: uuid.UUID, user_id: uuid.UUID) -> ProjectMember | None:
    return db.get(ProjectMember, {"project_id": project_id, "user_id": user_id})


def upsert_member(
    db: Session, actor: User, project: Project, user_id: uuid.UUID, role: ProjectRole
) -> ProjectMember:
    member = _get_active_user(db, user_id)
    membership = _get_membership(db, project.id, user_id)
    if membership is None:
        membership = ProjectMember(project_id=project.id, user_id=user_id, role=role)
        db.add(membership)
        notify_added_members(db, actor, project, [user_id])
    else:
        is_demoting_lead = membership.role == ProjectRole.LEAD and role != ProjectRole.LEAD
        if is_demoting_lead and _count_leads(db, project.id) <= 1:
            raise ConflictError(LAST_LEAD)
        membership.role = role
    _record(db, actor, project.id, "member_set", {"member": member.full_name, "role": role})
    db.commit()
    db.refresh(membership)
    return membership


def remove_member(db: Session, actor: User, project: Project, user_id: uuid.UUID) -> None:
    membership = _get_membership(db, project.id, user_id)
    if membership is None:
        raise NotFoundError("Ce membre ne fait pas partie du projet.")
    if membership.role == ProjectRole.LEAD and _count_leads(db, project.id) <= 1:
        raise ConflictError(LAST_LEAD)
    _record(db, actor, project.id, "member_removed", {"member": membership.user.full_name})
    db.delete(membership)
    db.commit()
