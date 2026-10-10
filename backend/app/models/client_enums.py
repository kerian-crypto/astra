"""Énumérations du domaine client (Astra Client)."""

from enum import StrEnum


class ClientPermission(StrEnum):
    """Permissions individuelles d'un compte client, vérifiées côté serveur."""

    VIEW_PROJECT = "view_project"
    VIEW_DOCUMENT = "view_document"
    DOWNLOAD_DOCUMENT = "download_document"
    VIEW_INVOICE = "view_invoice"
    SUBMIT_PAYMENT_PROOF = "submit_payment_proof"
    VIEW_CONTRACT = "view_contract"
    SEND_MESSAGE = "send_message"
    CREATE_TICKET = "create_ticket"
    VALIDATE_DELIVERABLE = "validate_deliverable"
    VIEW_FINANCIAL_DATA = "view_financial_data"
    MANAGE_COMPANY_USERS = "manage_company_users"
    SUBMIT_BRIEF = "submit_brief"  # questionnaire de cadrage d'un nouveau projet


# Droits par défaut d'un nouveau compte : tout sauf la finance et
# l'administration de l'entreprise, accordées explicitement par Astra.
DEFAULT_CLIENT_PERMISSIONS = (
    ClientPermission.VIEW_PROJECT,
    ClientPermission.VIEW_DOCUMENT,
    ClientPermission.DOWNLOAD_DOCUMENT,
    ClientPermission.SEND_MESSAGE,
    ClientPermission.CREATE_TICKET,
    ClientPermission.VALIDATE_DELIVERABLE,
    ClientPermission.SUBMIT_BRIEF,
)

# Compte créé par le client lui-même (inscription) : son entreprise est
# neuve et vide, il peut décrire son projet et échanger avec Astra.
SELF_REGISTERED_PERMISSIONS = (*DEFAULT_CLIENT_PERMISSIONS, ClientPermission.MANAGE_COMPANY_USERS)


class BriefStatus(StrEnum):
    DRAFT = "draft"  # en cours de saisie par le client
    SUBMITTED = "submitted"  # transmis à Astra
    IN_REVIEW = "in_review"  # étudié par un membre d'Astra
    CONVERTED = "converted"  # projet créé à partir du cahier des charges
    ARCHIVED = "archived"


class InvitationPurpose(StrEnum):
    ACTIVATION = "activation"  # premier accès : le client choisit son mot de passe
    PASSWORD_RESET = "password_reset"  # noqa: S105 — nouveau mot de passe, lien émis par Astra


class ClientProjectStatus(StrEnum):
    """Statut affiché au client, piloté par Astra Hub (cahier des charges §16)."""

    PLANNING = "planning"
    IN_PROGRESS = "in_progress"
    WAITING_CLIENT = "waiting_client"
    IN_VALIDATION = "in_validation"
    CHANGES_REQUESTED = "changes_requested"
    IN_CORRECTION = "in_correction"
    DONE = "done"
    SUSPENDED = "suspended"
    CANCELLED = "cancelled"


class DocumentVisibility(StrEnum):
    INTERNAL = "internal"  # Astra Hub uniquement (défaut)
    CLIENT = "client"  # visible de l'entreprise cliente du projet


class DeliverableStatus(StrEnum):
    DRAFT = "draft"  # en préparation, invisible du client
    PUBLISHED = "published"  # transmis, sans validation demandée
    AWAITING_VALIDATION = "awaiting_validation"
    APPROVED = "approved"
    CHANGES_REQUESTED = "changes_requested"


class ReviewAction(StrEnum):
    APPROVE = "approve"
    REQUEST_CHANGES = "request_changes"


class ConversationKind(StrEnum):
    GENERAL = "general"
    PROJECT = "project"
    DELIVERABLE = "deliverable"
    TICKET = "ticket"


class TicketType(StrEnum):
    TECHNICAL = "technical"
    QUESTION = "question"
    CHANGE = "change"
    COMPLAINT = "complaint"
    ADMINISTRATIVE = "administrative"
    DOCUMENT_REQUEST = "document_request"
    OTHER = "other"


class TicketStatus(StrEnum):
    NEW = "new"
    ACKNOWLEDGED = "acknowledged"
    IN_PROGRESS = "in_progress"
    WAITING_CLIENT = "waiting_client"
    RESOLVED = "resolved"
    CLOSED = "closed"


class TicketPriority(StrEnum):
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"
    URGENT = "urgent"


class InvoiceStatus(StrEnum):
    ISSUED = "issued"
    CANCELLED = "cancelled"


class InvoicePaymentStatus(StrEnum):
    """État de paiement d'une facture, calculé à partir des déclarations (§31)."""

    UNPAID = "unpaid"
    PAYMENT_DECLARED = "payment_declared"
    UNDER_REVIEW = "under_review"
    CONFIRMED = "confirmed"
    REJECTED = "rejected"
    PARTIALLY_CONFIRMED = "partially_confirmed"


class PaymentDeclarationStatus(StrEnum):
    DECLARED = "declared"
    UNDER_REVIEW = "under_review"
    CONFIRMED = "confirmed"
    REJECTED = "rejected"


class PaymentMethod(StrEnum):
    BANK_TRANSFER = "bank_transfer"
    MOBILE_MONEY = "mobile_money"
    CASH = "cash"
    CHECK = "check"
    CARD = "card"
    OTHER = "other"


class ContractStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    EXPIRED = "expired"
    TERMINATED = "terminated"


class ClientNotificationKind(StrEnum):
    """Événements notifiés au client (§49)."""

    NEW_MESSAGE = "new_message"
    PROJECT_ADDED = "project_added"
    PROJECT_UPDATED = "project_updated"
    DELIVERABLE_READY = "deliverable_ready"
    VALIDATION_REQUIRED = "validation_required"
    DOCUMENT_AVAILABLE = "document_available"
    INVOICE_CREATED = "invoice_created"
    PAYMENT_CONFIRMED = "payment_confirmed"
    PAYMENT_REJECTED = "payment_rejected"
    TICKET_UPDATED = "ticket_updated"
    CONTRACT_AVAILABLE = "contract_available"
