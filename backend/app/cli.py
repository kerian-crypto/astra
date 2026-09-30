"""Outils d'administration en ligne de commande.

Usage :
    python -m app.cli create-admin --email admin@astra.example --name "Admin Astra"
    python -m app.cli seed-channels

Le mot de passe est lu depuis ASTRA_ADMIN_PASSWORD ou demandé de façon
interactive ; il n'est jamais passé en argument (visible dans `ps`).
"""

import argparse
import getpass
import os
import sys

from pydantic import ValidationError
from sqlalchemy import select

from app.db.session import get_session_factory
from app.models import Channel
from app.models.enums import AccessLevel, ChannelKind
from app.schemas.user import UserCreate
from app.services import user_service
from app.services.errors import ConflictError


def _read_password() -> str:
    from_env = os.environ.get("ASTRA_ADMIN_PASSWORD")
    if from_env:
        return from_env
    password = getpass.getpass("Mot de passe : ")
    if password != getpass.getpass("Confirmation : "):
        sys.exit("Les mots de passe ne correspondent pas.")
    return password


def create_admin(email: str, full_name: str) -> None:
    try:
        data = UserCreate(
            email=email,
            password=_read_password(),
            full_name=full_name,
            access_level=AccessLevel.ADMIN,
        )
    except ValidationError as exc:
        sys.exit(f"Données invalides :\n{exc}")

    with get_session_factory()() as db:
        try:
            user = user_service.create_user(db, data)
        except ConflictError as exc:
            sys.exit(exc.detail)
    print(f"Administrateur créé : {user.email} ({user.id})")


# Canaux proposés par la spec (§5). #annonces : publication réservée.
DEFAULT_CHANNELS = [
    ("général", "Discussions générales d'Astra", False),
    ("annonces", "Annonces officielles", True),
    ("développement", "Développement et technique", False),
    ("marketing", "Marketing et communication", False),
    ("design", "Design et UX", False),
    ("direction", "Direction", False),
    ("projets", "Suivi transverse des projets", False),
]


def seed_channels() -> None:
    with get_session_factory()() as db:
        existing = set(db.scalars(select(Channel.name).where(Channel.kind == ChannelKind.PUBLIC)))
        for name, description, announcements_only in DEFAULT_CHANNELS:
            if name not in existing:
                db.add(
                    Channel(
                        kind=ChannelKind.PUBLIC,
                        name=name,
                        description=description,
                        announcements_only=announcements_only,
                    )
                )
                print(f"Canal créé : #{name}")
        db.commit()


def main() -> None:
    parser = argparse.ArgumentParser(prog="astra-hub")
    commands = parser.add_subparsers(dest="command", required=True)
    admin = commands.add_parser("create-admin", help="Créer un compte administrateur")
    admin.add_argument("--email", required=True)
    admin.add_argument("--name", required=True)
    commands.add_parser("seed-channels", help="Créer les canaux publics par défaut")

    args = parser.parse_args()
    if args.command == "create-admin":
        create_admin(args.email, args.name)
    elif args.command == "seed-channels":
        seed_channels()


if __name__ == "__main__":
    main()
