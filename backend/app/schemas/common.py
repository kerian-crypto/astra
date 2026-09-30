from typing import ClassVar, Self

from pydantic import BaseModel, model_validator


class PartialUpdate(BaseModel):
    """Base des schémas PATCH : un champ absent n'est pas modifié, mais un
    champ obligatoire en base ne peut pas être explicitement mis à null."""

    NON_NULLABLE: ClassVar[frozenset[str]] = frozenset()

    @model_validator(mode="after")
    def reject_explicit_nulls(self) -> Self:
        nulled = sorted(
            name
            for name in self.model_fields_set & self.NON_NULLABLE
            if getattr(self, name) is None
        )
        if nulled:
            raise ValueError(f"Ces champs ne peuvent pas être null : {', '.join(nulled)}")
        return self
