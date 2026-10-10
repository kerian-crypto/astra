"""Libellés français du domaine client, pour les notifications."""

from decimal import Decimal

from app.models.client_enums import ClientProjectStatus, TicketStatus

CLIENT_STATUS_LABELS = {
    ClientProjectStatus.PLANNING: "Planification",
    ClientProjectStatus.IN_PROGRESS: "En cours",
    ClientProjectStatus.WAITING_CLIENT: "En attente de votre retour",
    ClientProjectStatus.IN_VALIDATION: "En validation",
    ClientProjectStatus.CHANGES_REQUESTED: "Modification demandée",
    ClientProjectStatus.IN_CORRECTION: "En correction",
    ClientProjectStatus.DONE: "Terminé",
    ClientProjectStatus.SUSPENDED: "Suspendu",
    ClientProjectStatus.CANCELLED: "Annulé",
}

TICKET_STATUS_LABELS = {
    TicketStatus.NEW: "Nouveau",
    TicketStatus.ACKNOWLEDGED: "Pris en charge",
    TicketStatus.IN_PROGRESS: "En cours",
    TicketStatus.WAITING_CLIENT: "En attente de votre réponse",
    TicketStatus.RESOLVED: "Résolu",
    TicketStatus.CLOSED: "Fermé",
}


def format_money(amount: Decimal, currency: str) -> str:
    """« 1 500 000 FCFA » : montants lisibles dans les textes envoyés au client."""
    if currency in ("XOF", "XAF"):
        return f"{round(amount):,}".replace(",", "\u202f") + " FCFA"
    return f"{amount:,.2f}".replace(",", "\u202f").replace(".", ",") + f" {currency}"
