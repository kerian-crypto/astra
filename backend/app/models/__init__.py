"""Import de tous les modèles pour qu'Alembic les voie dans Base.metadata."""

from app.models.activity import ActivityLog
from app.models.ai import AIConversation, AIMessage
from app.models.chat import Channel, ChannelMember, Message, MessageReaction
from app.models.device import DeviceToken
from app.models.document import Document
from app.models.meeting import Decision, Meeting, MeetingParticipant
from app.models.notification import Notification
from app.models.project import Project, ProjectMember
from app.models.refresh_token import RefreshToken
from app.models.task import ChecklistItem, ProjectPhase, Task, TaskComment, TaskDependency
from app.models.user import User

__all__ = [
    "AIConversation",
    "AIMessage",
    "ActivityLog",
    "Channel",
    "ChannelMember",
    "ChecklistItem",
    "Decision",
    "DeviceToken",
    "Document",
    "Meeting",
    "MeetingParticipant",
    "Message",
    "MessageReaction",
    "Notification",
    "Project",
    "ProjectMember",
    "ProjectPhase",
    "RefreshToken",
    "Task",
    "TaskComment",
    "TaskDependency",
    "User",
]
