"""
RDC Agent — Tests API: auto-detecta runner e executa testes
"""
from __future__ import annotations

import asyncio
import re
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from database import get_db
from models.project import Project
from models.test_run import TestRun
from schemas.tests import TestRunRequest, TestRunResponse
from services.process_manager import run_and_collect

router = APIRouter(prefix="/api/tests", tags=["Tests"])

RUNNERS = {
    "pytest": ["python", "-m", "pytest", "--tb=short", "-q"],
    "unittest": ["python", "-m", "unittest", "discover", "-v"],
    "jest": ["npx", "jest", "--no-coverage"],
    "npm_test": ["npm", "test", "--", "--watchAll=false"],
    "cargo": ["cargo", "test"],
}

DETECT_ORDER = [
    ("pytest.ini", "pytest"),
    ("setup.cfg", "pytest"),
    ("pyproject.toml", "pytest"),
    ("jest.config.js", "jest"),
    ("jest.config.ts", "jest"),
    ("package.json", "npm_test"),
    ("Cargo.toml", "cargo"),
]


def _detect_runner(project_path: str) -> str:
    p = Path(project_path)
    for filename, runner in DETECT_ORDER:
        if (p / filename).exists():
            return runner
    return "pytest"  # fallback


def _parse_pytest_output(output: str) -> tuple[int, int, int]:
    passed = failed = skipped = 0
    m = re.search(r"(\d+) passed", output)
    if m:
        passed = int(m.group(1))
    m = re.search(r"(\d+) failed", output)
    if m:
        failed = int(m.group(1))
    m = re.search(r"(\d+) (skipped|warning)", output)
    if m:
        skipped = int(m.group(1))
    return passed, failed, skipped


async def _project_path(project_id: int, db: AsyncSession) -> str:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")
    return project.path


@router.post("/{project_id}/run", response_model=TestRunResponse)
async def run_tests(
    project_id: int,
    body: TestRunRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> TestRunResponse:
    path = await _project_path(project_id, db)
    runner = body.runner or _detect_runner(path)
    base_cmd = RUNNERS.get(runner, ["pytest"])
    cmd = base_cmd + body.extra_args

    test_run = TestRun(
        project_id=project_id,
        runner=runner,
        command=" ".join(cmd),
        status="running",
    )
    db.add(test_run)
    await db.commit()
    await db.refresh(test_run)

    start = time.monotonic()
    output, code = await run_and_collect(cmd, cwd=path, timeout=300)
    elapsed = round(time.monotonic() - start, 2)

    passed, failed, skipped = _parse_pytest_output(output)
    test_run.status = "passed" if code == 0 else "failed"
    test_run.output = output
    test_run.execution_time_s = elapsed
    test_run.passed = passed
    test_run.failed = failed
    test_run.skipped = skipped
    test_run.finished_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(test_run)
    return TestRunResponse.model_validate(test_run)


@router.get("/{project_id}/history", response_model=list[TestRunResponse])
async def test_history(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[TestRunResponse]:
    result = await db.execute(
        select(TestRun)
        .where(TestRun.project_id == project_id)
        .order_by(TestRun.created_at.desc())
        .limit(20)
    )
    return [TestRunResponse.model_validate(r) for r in result.scalars().all()]
