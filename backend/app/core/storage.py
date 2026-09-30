import hashlib
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO

CHUNK_SIZE = 1024 * 1024


class FileTooLargeError(Exception):
    pass


@dataclass(frozen=True)
class StoredFile:
    key: str
    size_bytes: int
    sha256: str
    head: bytes  # premiers octets, pour vérifier la signature du format


class LocalFileStorage:
    """Stockage sur disque sous des noms générés : aucun nom ou chemin fourni
    par l'utilisateur n'est utilisé (pas de traversée de répertoire)."""

    HEAD_BYTES = 16

    def __init__(self, root: str | Path) -> None:
        self._root = Path(root)

    def path(self, key: str) -> Path:
        # `key` est toujours un hex UUID généré ici ; on le revérifie quand même.
        return self._root / uuid.UUID(hex=key).hex

    def save(self, source: BinaryIO, max_bytes: int) -> StoredFile:
        self._root.mkdir(parents=True, exist_ok=True)
        key = uuid.uuid4().hex
        target = self.path(key)
        digest = hashlib.sha256()
        size = 0
        head = b""
        try:
            with target.open("xb") as output:
                while chunk := source.read(CHUNK_SIZE):
                    size += len(chunk)
                    if size > max_bytes:
                        raise FileTooLargeError
                    if len(head) < self.HEAD_BYTES:
                        head += chunk[: self.HEAD_BYTES - len(head)]
                    digest.update(chunk)
                    output.write(chunk)
        except BaseException:
            target.unlink(missing_ok=True)
            raise
        return StoredFile(key=key, size_bytes=size, sha256=digest.hexdigest(), head=head)

    def delete(self, key: str) -> None:
        self.path(key).unlink(missing_ok=True)
