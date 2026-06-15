"""
Schemas de Testes
"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class TestRunRequest(BaseModel):
    project_id: int
    runner: str | None = None  # None = auto-detectar
    extra_args: list[str] = []


class TestRunResponse(BaseModel):
    id: int
    project_id: int
    runner: str
    command: str
    status: str
    passed: int | None
    failed: int | None
    skipped: int | None
    execution_time_s: float | None
    output: str | None
    created_at: datetime
    finished_at: datetime | None

    model_config = {"from_attributes": True}
