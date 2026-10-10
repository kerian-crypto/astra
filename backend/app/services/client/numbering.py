"""Numéros lisibles et séquentiels par année : AST-2026-042, SUP-2026-014."""

import zlib
from datetime import date

from sqlalchemy import func, select, text
from sqlalchemy.orm import InstrumentedAttribute, Session


def next_number(db: Session, column: InstrumentedAttribute[str], prefix: str) -> str:
    """Le verrou consultatif (relâché au commit) sérialise les créations
    simultanées : deux factures ne reçoivent jamais le même numéro."""
    db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": zlib.crc32(prefix.encode())})
    stem = f"{prefix}-{date.today().year}-"
    last = db.scalar(select(func.max(column)).where(column.like(f"{stem}%")))
    sequence = int(last.removeprefix(stem)) + 1 if last else 1
    return f"{stem}{sequence:03d}"
