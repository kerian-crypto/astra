from enum import StrEnum


class AccessLevel(StrEnum):
    """Niveau d'accès global d'un membre dans Astra."""

    MEMBER = "member"
    MANAGER = "manager"  # peut créer des projets
    ADMIN = "admin"  # gère les membres, voit tous les projets


class ProjectRole(StrEnum):
    """Rôle d'un membre au sein d'un projet donné."""

    VIEWER = "viewer"
    CONTRIBUTOR = "contributor"
    LEAD = "lead"  # responsable : modifie le projet et gère ses membres


class ProjectStatus(StrEnum):
    IDEA = "idea"
    PLANNING = "planning"
    ACTIVE = "active"
    REVIEW = "review"
    DONE = "done"
    ARCHIVED = "archived"


class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class TaskStatus(StrEnum):
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    REVIEW = "review"
    DONE = "done"


class MeetingStatus(StrEnum):
    PLANNED = "planned"
    DONE = "done"
    CANCELLED = "cancelled"


class DecisionStatus(StrEnum):
    PROPOSED = "proposed"
    VALIDATED = "validated"
    REJECTED = "rejected"


class ChannelKind(StrEnum):
    PUBLIC = "public"  # ouvert à tous les membres (#général, #annonces…)
    PRIVATE = "private"  # groupe sur invitation
    PROJECT = "project"  # espace de discussion d'un projet (membres du projet)
    DIRECT = "direct"  # conversation entre deux membres


class NotificationKind(StrEnum):
    MENTION = "mention"
    TASK_ASSIGNED = "task_assigned"
    MEETING_INVITE = "meeting_invite"
    REGISTRATION_REQUEST = "registration_request"


class DocumentKind(StrEnum):
    SPECIFICATION = "specification"  # cahier des charges, spécifications
    DESIGN = "design"
    TECHNICAL = "technical"
    CONTRACT = "contract"
    MINUTES = "minutes"  # comptes rendus
    GUIDE = "guide"
    DELIVERABLE = "deliverable"  # livrables, fichiers de production
    LESSONS = "lessons"  # retours d'expérience
    OTHER = "other"


class AIRole(StrEnum):
    USER = "user"
    ASSISTANT = "assistant"


class AIMessageStatus(StrEnum):
    PENDING = "pending"  # Ronda génère la réponse en arrière-plan
    DONE = "done"
    FAILED = "failed"


class AIFocusType(StrEnum):
    """Écran de l'app consulté par le membre quand il interroge Ronda."""

    PROJECT = "project"
    TASK = "task"
    MEETING = "meeting"
    CHANNEL = "channel"
    DOCUMENT = "document"
    DECISION = "decision"


class AIActionKind(StrEnum):
    """Actions que Ronda peut proposer ; le membre les valide avant exécution."""

    CREATE_PROJECT = "create_project"
    SCHEDULE_MEETING = "schedule_meeting"
    CREATE_TASK = "create_task"
    CREATE_DECISION = "create_decision"


class AIActionStatus(StrEnum):
    PROPOSED = "proposed"
    APPLIED = "applied"
    DISMISSED = "dismissed"


class AttachmentKind(StrEnum):
    """Pièce jointe d'un message du chat."""

    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"  # dont les messages vocaux enregistrés dans l'app
    FILE = "file"
