import uuid
from unittest.mock import patch

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import (
    InvalidTokenError,
    create_access_token,
    decode_access_token,
    hash_refresh_token,
)
from app.models.enums import ProjectRole
from app.services.permissions import has_project_role


@pytest.fixture
def settings() -> Settings:
    return Settings(
        DATABASE_URL="postgresql+psycopg://u:p@localhost/db",
        SECRET_KEY="k" * 40,
    )


def test_settings_refuse_short_secret_key():
    with pytest.raises(ValidationError):
        Settings(DATABASE_URL="postgresql+psycopg://u:p@localhost/db", SECRET_KEY="short")


def test_settings_split_cors_origins_from_string(settings):
    parsed = settings.model_validate(
        {**settings.model_dump(), "BACKEND_CORS_ORIGINS": "https://a.test, https://b.test,"}
    )

    assert parsed.BACKEND_CORS_ORIGINS == ["https://a.test", "https://b.test"]


def test_settings_reject_wildcard_cors(settings):
    with pytest.raises(ValidationError):
        settings.model_validate({**settings.model_dump(), "BACKEND_CORS_ORIGINS": "*"})


def test_access_token_round_trip(settings):
    user_id = uuid.uuid4()

    assert decode_access_token(create_access_token(user_id, settings), settings) == user_id


def test_decode_rejects_garbage(settings):
    with pytest.raises(InvalidTokenError):
        decode_access_token("not-a-jwt", settings)


def test_refresh_token_hash_is_deterministic_and_not_the_token():
    assert hash_refresh_token("abc") == hash_refresh_token("abc")
    assert hash_refresh_token("abc") != "abc"


@pytest.mark.parametrize(
    ("role", "minimum", "expected"),
    [
        (None, ProjectRole.VIEWER, False),
        (ProjectRole.VIEWER, ProjectRole.VIEWER, True),
        (ProjectRole.VIEWER, ProjectRole.CONTRIBUTOR, False),
        (ProjectRole.CONTRIBUTOR, ProjectRole.VIEWER, True),
        (ProjectRole.LEAD, ProjectRole.LEAD, True),
        (ProjectRole.CONTRIBUTOR, ProjectRole.LEAD, False),
    ],
)
def test_project_role_hierarchy(role, minimum, expected):
    assert has_project_role(role, minimum) is expected


def test_rate_limiter_blocks_after_max_attempts_and_resets():
    limiter = SlidingWindowRateLimiter(max_attempts=2, window_seconds=60)
    limiter.record_failure("k")
    assert not limiter.is_blocked("k")
    limiter.record_failure("k")
    assert limiter.is_blocked("k")
    assert not limiter.is_blocked("other")
    limiter.reset("k")
    assert not limiter.is_blocked("k")


def test_rate_limiter_forgets_attempts_outside_window():
    limiter = SlidingWindowRateLimiter(max_attempts=1, window_seconds=10)
    with patch("app.core.rate_limit.time.monotonic", return_value=100.0):
        limiter.record_failure("k")
        assert limiter.is_blocked("k")
    with patch("app.core.rate_limit.time.monotonic", return_value=111.0):
        assert not limiter.is_blocked("k")
