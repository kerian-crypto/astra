class ServiceError(Exception):
    """Erreur métier traduite en réponse HTTP par la couche API."""

    status_code = 400

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class AuthenticationError(ServiceError):
    status_code = 401


class PermissionDeniedError(ServiceError):
    status_code = 403


class NotFoundError(ServiceError):
    status_code = 404


class ConflictError(ServiceError):
    status_code = 409


class RateLimitedError(ServiceError):
    status_code = 429
