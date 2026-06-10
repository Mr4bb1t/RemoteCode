"""
Schemas de Projeto
"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, field_validator


class ProjectCreate(BaseModel):
    name: str
    path: str
    language: str | None = None
    description: str | None = None

    @field_validator("path")
    @classmethod
    def path_must_not_be_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("path não pode ser vazio")
        return v


class ProjectUpdate(BaseModel):
    name: str | None = None
    language: str | None = None
    description: str | None = None


class ProjectResponse(BaseModel):
    id: int
    name: str
    path: str
    language: str | None
    description: str | None
    is_favorite: bool
    current_branch: str | None = None
    last_modified: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
