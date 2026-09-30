"""Règles d'autorisation d'ASTRA HUB.

Toute décision d'accès passe par ce module. Les routes (et plus tard l'IA)
ne doivent jamais interroger les projets sans passer par
`visible_projects_statement` ou `get_project_role`.
"""

import uuid

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from app.models import Project, ProjectMember, User
from app.models.enums import AccessLevel, ProjectRole

_PROJECT_ROLE_RANK = {
    ProjectRole.VIEWER: 1,
    ProjectRole.CONTRIBUTOR: 2,
    ProjectRole.LEAD: 3,
}


def is_admin(user: User) -> bool:
    return user.access_level == AccessLevel.ADMIN


def can_create_project(user: User) -> bool:
    return user.access_level in (AccessLevel.MANAGER, AccessLevel.ADMIN)


def visible_projects_statement(user: User) -> Select[tuple[Project]]:
    """Projets que l'utilisateur a le droit de voir : tous pour un admin,
    sinon uniquement ceux dont il est membre."""
    statement = select(Project)
    if is_admin(user):
        return statement
    return statement.join(ProjectMember).where(ProjectMember.user_id == user.id)


def get_project_role(db: Session, user: User, project: Project) -> ProjectRole | None:
    """Rôle effectif de l'utilisateur sur le projet (None = aucun accès).
    Un admin a les droits d'un responsable sur tous les projets."""
    if is_admin(user):
        return ProjectRole.LEAD
    return db.scalar(
        select(ProjectMember.role).where(
            ProjectMember.project_id == project.id,
            ProjectMember.user_id == user.id,
        )
    )


def has_project_role(role: ProjectRole | None, minimum: ProjectRole) -> bool:
    return role is not None and _PROJECT_ROLE_RANK[role] >= _PROJECT_ROLE_RANK[minimum]


def visible_project_ids(user: User) -> Select[tuple[uuid.UUID]]:
    """Sous-requête des identifiants de projets visibles, à utiliser dans
    `Model.project_id.in_(...)` pour filtrer toute donnée rattachée à un projet."""
    statement = select(Project.id)
    if is_admin(user):
        return statement
    return statement.join(ProjectMember).where(ProjectMember.user_id == user.id)
