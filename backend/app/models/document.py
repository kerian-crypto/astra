import uuid

from sqlalchemy import BigInteger, Computed, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, string_enum
from app.models.client_enums import DocumentVisibility
from app.models.enums import DocumentKind
from app.models.user import User


class Document(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Document d'un projet, ou document général d'Astra (project_id nul).

    Le fichier est stocké sous un nom généré (`storage_key`), jamais sous le
    nom fourni par l'utilisateur. Le texte extrait alimente la recherche.
    """

    __tablename__ = "documents"
    __table_args__ = (Index("ix_documents_search", "search_vector", postgresql_using="gin"),)

    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    kind: Mapped[DocumentKind] = mapped_column(string_enum(DocumentKind))
    filename: Mapped[str] = mapped_column(String(255))
    content_type: Mapped[str] = mapped_column(String(120))
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(String(64))
    storage_key: Mapped[str] = mapped_column(String(80), unique=True)
    text_content: Mapped[str | None] = mapped_column(Text)
    uploaded_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    search_vector: Mapped[str] = mapped_column(
        TSVECTOR,
        Computed(
            "to_tsvector('french', coalesce(title, '') || ' ' || coalesce(text_content, ''))",
            persisted=True,
        ),
    )

    # Astra Client : seuls les documents `client` d'un projet rattaché à une
    # entreprise cliente lui sont visibles. Tout document est interne par défaut.
    visibility: Mapped[DocumentVisibility] = mapped_column(
        string_enum(DocumentVisibility),
        default=DocumentVisibility.INTERNAL,
        server_default=DocumentVisibility.INTERNAL.value,
    )
    # Versions successives d'un même document : même groupe, numéro croissant.
    # Le groupe d'un document initial est son propre identifiant.
    version_group_id: Mapped[uuid.UUID | None] = mapped_column(index=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1")

    uploaded_by: Mapped[User | None] = relationship(lazy="joined")
