"""
RDC Agent — Antigravity API
Executa prompts, armazena histórico, permite aprovação/rejeição de mudanças.
"""
from __future__ import annotations

import asyncio
import json
import time
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from database import get_db
from models.antigravity import AntigravityRun
from models.project import Project
from schemas.antigravity import (
    AntigravityApproveRequest,
    AntigravityRunRequest,
    AntigravityRunResponse,
    FileDiff,
)
from services import antigravity_service
from services.git_service import get_diff

router = APIRouter(prefix="/api/antigravity", tags=["Antigravity"])


async def _project_path(project_id: int, db: AsyncSession) -> str:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")
    return project.path


@router.post("/run")
async def run_antigravity(
    body: AntigravityRunRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> StreamingResponse:
    """
    Executa o Antigravity CLI e faz streaming do output em tempo real (SSE).
    Ao finalizar, salva o histórico no banco.
    """
    path = await _project_path(body.project_id, db)

    run = AntigravityRun(
        project_id=body.project_id,
        prompt=body.prompt,
        status="running",
    )
    db.add(run)
    await db.commit()
    await db.refresh(run)
    run_id = run.id

    async def event_generator():
        output_lines: list[str] = []
        start = time.monotonic()

        yield f"data: {{\"type\":\"start\",\"run_id\":{run_id}}}\n\n"

        try:
            async for line in antigravity_service.run_prompt(path, body.prompt):
                output_lines.append(line)
                safe = line.replace('"', '\\"').replace("\n", "\\n")
                yield f'data: {{"type":"output","line":"{safe}"}}\n\n'
        except Exception as e:
            yield f'data: {{"type":"error","message":"{str(e)}"}}\n\n'

        elapsed = round(time.monotonic() - start, 2)
        output_log = "".join(output_lines)
        files_changed = antigravity_service.detect_changed_files(path, output_log)

        # Atualizar banco (nova sessão para evitar conflito)
        async with db.__class__(bind=db.get_bind()) as new_session:
            r = await new_session.get(AntigravityRun, run_id)
            if r:
                r.status = "success"
                r.execution_time_s = elapsed
                r.output_log = output_log
                r.files_changed = json.dumps(files_changed)
                r.finished_at = datetime.now(timezone.utc)
                await new_session.commit()

        fc_json = json.dumps(files_changed)
        yield f'data: {{"type":"done","run_id":{run_id},"elapsed":{elapsed},"files_changed":{fc_json}}}\n\n'

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/history/{project_id}", response_model=list[AntigravityRunResponse])
async def get_history(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[AntigravityRunResponse]:
    result = await db.execute(
        select(AntigravityRun)
        .where(AntigravityRun.project_id == project_id)
        .order_by(AntigravityRun.created_at.desc())
        .limit(50)
    )
    runs = result.scalars().all()
    return [
        AntigravityRunResponse(
            **{k: v for k, v in run.__dict__.items() if not k.startswith("_")},
            files_changed=json.loads(run.files_changed) if run.files_changed else None,
        )
        for run in runs
    ]


@router.get("/run/{run_id}", response_model=AntigravityRunResponse)
async def get_run(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> AntigravityRunResponse:
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")
    return AntigravityRunResponse(
        **{k: v for k, v in run.__dict__.items() if not k.startswith("_")},
        files_changed=json.loads(run.files_changed) if run.files_changed else None,
    )


@router.get("/run/{run_id}/diff", response_model=list[FileDiff])
async def get_run_diff(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[FileDiff]:
    """Retorna o diff Git dos arquivos modificados pela execução."""
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")

    result = await db.execute(select(Project).where(Project.id == run.project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")

    files = json.loads(run.files_changed) if run.files_changed else []
    diffs: list[FileDiff] = []
    for f in files:
        diff_resp = get_diff(project.path, f)
        diffs.append(FileDiff(path=f, status="modified", diff=diff_resp.diff))
    return diffs


@router.post("/run/{run_id}/approve")
async def approve_run(
    run_id: int,
    body: AntigravityApproveRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Aprova ou rejeita as mudanças de uma execução do Antigravity.
    Rejeitar faz git checkout -- . para restaurar os arquivos.
    """
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")

    result = await db.execute(select(Project).where(Project.id == run.project_id))
    project = result.scalar_one_or_none()

    if body.approve:
        run.status = "approved"
        message = "Mudanças aprovadas"
    else:
        run.status = "rejected"
        # Reverter mudanças via git checkout
        if project:
            try:
                import git
                repo = git.Repo(project.path)
                repo.git.checkout("--", ".")
            except Exception:
                pass
        message = "Mudanças rejeitadas e revertidas"

    await db.commit()
    return {"message": message, "status": run.status}
