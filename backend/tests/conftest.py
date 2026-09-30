"""Fixtures de test.

Les tests tournent contre une vraie base PostgreSQL désignée par
TEST_DATABASE_URL (jamais la base de dev : elle est vidée entre chaque test).
Le schéma est créé via les migrations Alembic, ce qui les teste au passage.
"""

import os
import tempfile
from collections.abc import Callable, Iterator

import pytest

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
if not TEST_DATABASE_URL:
    pytest.exit("TEST_DATABASE_URL doit pointer vers une base PostgreSQL dédiée aux tests.", 2)

os.environ["DATABASE_URL"] = TEST_DATABASE_URL
os.environ["SECRET_KEY"] = "test-secret-key-that-is-long-enough-0123456789"
os.environ["ENVIRONMENT"] = "test"
os.environ["UPLOAD_DIR"] = tempfile.mkdtemp(prefix="astra-uploads-")
# L'IA est remplacée par un faux modèle dans les tests (tests/test_ai.py).
os.environ.pop("AI_BASE_URL", None)

from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import delete, text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from alembic import command  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import get_engine, get_session_factory  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import Notification, User  # noqa: E402
from app.models.enums import AccessLevel  # noqa: E402
from app.schemas.user import UserCreate  # noqa: E402
from app.services import user_service  # noqa: E402

DEFAULT_PASSWORD = "correct-horse-battery"


@pytest.fixture(scope="session", autouse=True)
def _fast_password_hashing() -> Iterator[None]:
    """Argon2 avec des paramètres minimaux : les tests créent des centaines de
    comptes. Le hachage de production n'est pas modifié."""
    from pwdlib import PasswordHash
    from pwdlib.hashers.argon2 import Argon2Hasher

    from app.core import security

    original = security._password_hash
    security._password_hash = PasswordHash(
        (Argon2Hasher(time_cost=1, memory_cost=1024, parallelism=1),)
    )
    yield
    security._password_hash = original


@pytest.fixture(scope="session", autouse=True)
def _migrated_database() -> Iterator[None]:
    get_settings.cache_clear()
    config = Config("alembic.ini")
    command.downgrade(config, "base")
    command.upgrade(config, "head")
    yield
    get_engine().dispose()


@pytest.fixture(autouse=True)
def _clean_tables() -> Iterator[None]:
    yield
    tables = ", ".join(table.name for table in Base.metadata.sorted_tables)
    with get_engine().begin() as connection:
        connection.execute(text(f"TRUNCATE {tables} CASCADE"))


@pytest.fixture
def db() -> Iterator[Session]:
    with get_session_factory()() as session:
        yield session


@pytest.fixture
def client() -> Iterator[TestClient]:
    with TestClient(create_app()) as test_client:
        yield test_client


@pytest.fixture
def make_user(db: Session) -> Callable[..., User]:
    counter = iter(range(1_000))

    def _make(
        access_level: AccessLevel = AccessLevel.MEMBER,
        email: str | None = None,
        password: str = DEFAULT_PASSWORD,
        **extra: object,
    ) -> User:
        index = next(counter)
        data = UserCreate(
            email=email or f"member{index}@astra.example.com",
            password=password,
            full_name=f"Membre {index}",
            access_level=access_level,
            **extra,
        )
        return user_service.create_user(db, data)

    return _make


@pytest.fixture
def login(client: TestClient) -> Callable[[User], dict]:
    def _login(user: User, password: str = DEFAULT_PASSWORD) -> dict:
        response = client.post(
            "/api/v1/auth/login", json={"email": user.email, "password": password}
        )
        assert response.status_code == 200, response.text
        return response.json()

    return _login


@pytest.fixture
def auth_headers(login: Callable[[User], dict]) -> Callable[[User], dict[str, str]]:
    def _headers(user: User) -> dict[str, str]:
        return {"Authorization": f"Bearer {login(user)['access_token']}"}

    return _headers


@pytest.fixture
def team(client, db, make_user, auth_headers) -> dict:
    """Projet créé par un manager (lead), avec contributeur, lecteur et externe.

    `team["h"][role]` donne les en-têtes d'authentification de chaque rôle.
    """
    lead = make_user(AccessLevel.MANAGER)
    contributor, viewer, outsider = make_user(), make_user(), make_user()
    members = {"lead": lead, "contributor": contributor, "viewer": viewer, "outsider": outsider}
    headers = {role: auth_headers(user) for role, user in members.items()}
    project = client.post(
        "/api/v1/projects", headers=headers["lead"], json={"name": "MarketCM V2"}
    ).json()
    for role in ("contributor", "viewer"):
        client.put(
            f"/api/v1/projects/{project['id']}/members/{members[role].id}",
            headers=headers["lead"],
            json={"role": role},
        )
    # Les tests partent d'une boîte vide (sans les « ajouté au projet »).
    db.execute(delete(Notification))
    db.commit()
    return {"project": project, **members, "h": headers}


class RecordingPushSink:
    """Remplace Firebase : garde les push programmés au lieu de les envoyer."""

    def __init__(self) -> None:
        self.sent: list[tuple[frozenset, object]] = []

    def submit(self, user_ids: frozenset, message: object) -> None:
        self.sent.append((user_ids, message))

    def to(self, user: User) -> list:
        return [message for user_ids, message in self.sent if user.id in user_ids]

    def types_to(self, user: User) -> list[str]:
        return [message.type for message in self.to(user)]


@pytest.fixture
def pushes(client: TestClient) -> Iterator[RecordingPushSink]:
    """Après `client` : le démarrage de l'app désactive le push (pas de Firebase)."""
    from app.push import dispatcher

    sink = RecordingPushSink()
    dispatcher.configure(sink)
    yield sink
    dispatcher.configure(None)
