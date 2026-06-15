"""
Schemas do Antigravity CLI
"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class AntigravityRunRequest(BaseModel):
    project_id: int
    prompt: str
    model: str | None = None
    api_key: str | None = None


class AntigravityRunResponse(BaseModel):
    id: int
    project_id: int
    prompt: str
    status: str
    execution_time_s: float | None
    output_log: str | None
    files_changed: list[str] | None = None
    created_at: datetime
    finished_at: datetime | None

    model_config = {"from_attributes": True}


class AntigravityApproveRequest(BaseModel):
    run_id: int
    approve: bool  # True = aplicar, False = rejeitar


class FileDiff(BaseModel):
    path: str
    status: str  # modified | added | deleted
    diff: str | None = None
    old_content: str | None = None
    new_content: str | None = None
