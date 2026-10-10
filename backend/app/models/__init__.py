"""Import de tous les modèles pour qu'Alembic les voie dans Base.metadata."""

from app.models.activity import ActivityLog
from app.models.ai import AIConversation, AIMessage
from app.models.billing import Contract, Invoice, PaymentDeclaration
from app.models.brief import BriefFile, ProjectBrief
from app.models.chat import Channel, ChannelMember, Message, MessageReaction
from app.models.client import (
    ClientAccount,
    ClientCompany,
    ClientDeviceToken,
    ClientInvitation,
    ClientNotification,
    ClientRefreshToken,
)
from app.models.client_chat import ClientConversation, ClientConversationRead, ClientMessage
from app.models.deliverable import Deliverable, DeliverableReview, DeliverableVersion
from app.models.device import DeviceToken
from app.models.document import Document
from app.models.meeting import Decision, Meeting, MeetingParticipant
from app.models.notification import Notification
from app.models.project import Project, ProjectMember
from app.models.refresh_token import RefreshToken
from app.models.support import SupportTicket
from app.models.task import ChecklistItem, ProjectPhase, Task, TaskComment, TaskDependency
from app.models.user import User

__all__ = [
    "AIConversation",
    "AIMessage",
    "ActivityLog",
    "BriefFile",
    "Channel",
    "ChannelMember",
    "ChecklistItem",
    "ClientAccount",
    "ClientCompany",
    "ClientConversation",
    "ClientConversationRead",
    "ClientDeviceToken",
    "ClientInvitation",
    "ClientMessage",
    "ClientNotification",
    "ClientRefreshToken",
    "Contract",
    "Decision",
    "Deliverable",
    "DeliverableReview",
    "DeliverableVersion",
    "DeviceToken",
    "Document",
    "Invoice",
    "Meeting",
    "MeetingParticipant",
    "Message",
    "MessageReaction",
    "Notification",
    "PaymentDeclaration",
    "Project",
    "ProjectBrief",
    "ProjectMember",
    "ProjectPhase",
    "RefreshToken",
    "SupportTicket",
    "Task",
    "TaskComment",
    "TaskDependency",
    "User",
]
