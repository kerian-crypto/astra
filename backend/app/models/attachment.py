from sqlalchemy import BigInteger, String
from sqlalchemy.orm import Mapped, mapped_column


class AttachedFileMixin:
    """Fichier joint à une entité du domaine client (livrable, preuve de
    paiement, facture…), stocké sous un nom généré. Facultatif par défaut."""

    file_key: Mapped[str | None] = mapped_column(String(80), unique=True)
    file_name: Mapped[str | None] = mapped_column(String(255))
    file_content_type: Mapped[str | None] = mapped_column(String(120))
    file_size: Mapped[int | None] = mapped_column(BigInteger)
