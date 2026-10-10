import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.attachment import AttachedFileMixin
from app.models.client import ClientAccount
from app.models.client_enums import (
    ContractStatus,
    InvoiceStatus,
    PaymentDeclarationStatus,
    PaymentMethod,
)
from app.models.user import User

Money = Numeric(14, 2)


class Invoice(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    """Facture émise par Astra (§26). Le montant payé n'est jamais saisi :
    il découle des déclarations de paiement confirmées par Astra."""

    __tablename__ = "invoices"
    __table_args__ = (CheckConstraint("amount > 0", name="positive_amount"),)

    number: Mapped[str] = mapped_column(String(20), unique=True)  # AST-2026-042
    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL")
    )
    title: Mapped[str] = mapped_column(String(200))
    amount: Mapped[Decimal] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3), default="XOF")
    issue_date: Mapped[date]
    due_date: Mapped[date | None]
    status: Mapped[InvoiceStatus] = mapped_column(
        string_enum(InvoiceStatus), default=InvoiceStatus.ISSUED
    )
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )

    declarations: Mapped[list["PaymentDeclaration"]] = relationship(
        back_populates="invoice",
        lazy="selectin",
        order_by="PaymentDeclaration.created_at.desc()",
    )


class PaymentDeclaration(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    """Paiement effectué hors de l'application et déclaré par le client (§28).
    Jamais confirmé automatiquement : un membre d'Astra le vérifie (§30)."""

    __tablename__ = "payment_declarations"
    __table_args__ = (
        CheckConstraint("amount > 0", name="positive_amount"),
        CheckConstraint(
            "confirmed_amount IS NULL OR confirmed_amount >= 0", name="confirmed_amount_range"
        ),
    )

    invoice_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("invoices.id", ondelete="CASCADE"), index=True
    )
    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    declared_by_account_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("client_accounts.id", ondelete="SET NULL")
    )
    amount: Mapped[Decimal] = mapped_column(Money)
    paid_on: Mapped[date]
    method: Mapped[PaymentMethod] = mapped_column(string_enum(PaymentMethod))
    reference: Mapped[str | None] = mapped_column(String(120))
    note: Mapped[str | None] = mapped_column(Text)
    status: Mapped[PaymentDeclarationStatus] = mapped_column(
        string_enum(PaymentDeclarationStatus), default=PaymentDeclarationStatus.DECLARED
    )
    confirmed_amount: Mapped[Decimal | None] = mapped_column(Money)
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    invoice: Mapped[Invoice] = relationship(back_populates="declarations")
    declared_by: Mapped[ClientAccount | None] = relationship(lazy="joined")
    reviewed_by: Mapped[User | None] = relationship(lazy="joined")


class Contract(UUIDPrimaryKeyMixin, TimestampMixin, AttachedFileMixin, Base):
    """Contrat consultable par le client (§33), géré dans Astra Hub."""

    __tablename__ = "contracts"

    number: Mapped[str] = mapped_column(String(40), unique=True)
    company_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("client_companies.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL")
    )
    title: Mapped[str] = mapped_column(String(200))
    services: Mapped[str | None] = mapped_column(Text)  # prestations
    amount: Mapped[Decimal | None] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3), default="XOF")
    start_date: Mapped[date | None]
    end_date: Mapped[date | None]
    renewal_terms: Mapped[str | None] = mapped_column(String(300))
    payment_schedule: Mapped[str | None] = mapped_column(Text)  # échéances
    status: Mapped[ContractStatus] = mapped_column(
        string_enum(ContractStatus), default=ContractStatus.DRAFT
    )
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
