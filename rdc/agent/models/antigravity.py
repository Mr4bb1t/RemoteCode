"""
Model: AntigravityRun — Histórico de execuções do Antigravity CLI
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Float, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


class AntigravityRun(Base):
    __tablename__ = "antigravity_runs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    project_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        String(32), default="pending"
    )  # pending | running | success | error | rejected
    execution_time_s: Mapped[float | None] = mapped_column(Float, nullable=True)
    output_log: Mapped[str | None] = mapped_column(Text, nullable=True)
    files_changed: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )  # JSON list
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
