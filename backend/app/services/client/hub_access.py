"""Droits des membres d'Astra sur le domaine client (côté Astra Hub).

- Managers et administrateurs : gestion des entreprises, des comptes, des
  factures, des contrats, des paiements et de tous les tickets.
- Membres d'un projet rattaché à une entreprise : livrables (responsable) et
  conversations du projet.
- Assigné d'un ticket : ce ticket et sa conversation.
"""

from sqlalchemy.orm import Session

from app.models import ClientConversation, Project, SupportTicket, User
from app.models.enums import ProjectRole
from app.services import permissions
from app.services.errors import NotFoundError, PermissionDeniedError

CLIENT_ADMIN_ONLY = "Réservé aux managers et administrateurs."
CONVERSATION_NOT_FOUND = "Conversation introuvable."


def can_manage_clients(user: User) -> bool:
    return permissions.can_create_project(user)


def require_client_manager(user: User) -> None:
    if not can_manage_clients(user):
        raise PermissionDeniedError(CLIENT_ADMIN_ONLY)


def can_access_conversation(db: Session, user: User, conversation: ClientConversation) -> bool:
    if can_manage_clients(user):
        return True
    if conversation.project_id is not None:
        project = db.get(Project, conversation.project_id)
        if project is not None and permissions.has_project_role(
            permissions.get_project_role(db, user, project), ProjectRole.VIEWER
        ):
            return True
    if conversation.ticket_id is not None:
        ticket = db.get(SupportTicket, conversation.ticket_id)
        return ticket is not None and ticket.assignee_id == user.id
    return False


def require_conversation(
    db: Session, user: User, conversation: ClientConversation | None
) -> ClientConversation:
    if conversation is None or not can_access_conversation(db, user, conversation):
        raise NotFoundError(CONVERSATION_NOT_FOUND)
    return conversation
