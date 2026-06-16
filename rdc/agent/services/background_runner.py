"""
RDC Agent — Background AI Runner
Executa processos de IA em background, salva progresso periodicamente,
e permite reconexão para continuar acompanhar.
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from datetime import datetime, timezone
from typing import AsyncGenerator

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import AsyncSessionLocal
from models.antigravity import AntigravityRun



class RunState:
    """Estado de um processo de IA em execução."""
    def __init__(self, run_id: int, project_id: int, prompt: str):
        self.run_id = run_id
        self.project_id = project_id
        self.prompt = prompt
        self.status = "running"
        self.output_lines: list[str] = []
        self.files_changed: list[str] = []
        self.start_time = time.monotonic()
        self.subscribers: list[asyncio.Queue] = []
        self.task: asyncio.Task | None = None

    @property
    def elapsed(self) -> float:
        return round(time.monotonic() - self.start_time, 2)

    @property
    def output_log(self) -> str:
        return "".join(self.output_lines)

    def to_dict(self) -> dict:
        return {
            "run_id": self.run_id,
            "project_id": self.project_id,
            "status": self.status,
            "elapsed": self.elapsed,
            "output_lines": len(self.output_lines),
            "files_changed": self.files_changed,
        }


# Processos ativos em background
_active_runs: dict[int, RunState] = {}


def get_active_run(run_id: int) -> RunState | None:
    return _active_runs.get(run_id)


def get_all_active_runs() -> list[RunState]:
    return list(_active_runs.values())


async def _save_progress(state: RunState):
    """Salva progresso parcial no banco de dados."""
    try:
        async with AsyncSessionLocal() as session:
            run = await session.get(AntigravityRun, state.run_id)
            if run:
                run.output_log = state.output_log
                run.files_changed = json.dumps(state.files_changed) if state.files_changed else None
                run.execution_time_s = state.elapsed
                await session.commit()
    except Exception:
        pass


async def _notify_subscribers(state: RunState, event: dict):
    """Notifica todos os subscribers de um evento."""
    dead = []
    for q in state.subscribers:
        try:
            q.put_nowait(event)
        except asyncio.QueueFull:
            dead.append(q)
    for q in dead:
        state.subscribers.remove(q)


async def run_in_background(
    run_id: int,
    project_path: str,
    prompt: str,
    mimo_run_fn,
    project_id: int,
):
    """
    Executa o agente IA em background.
    Salva progresso a cada 10 linhas e ao finalizar.
    """
    state = RunState(run_id, project_id, prompt)
    _active_runs[run_id] = state

    save_interval = 10  # linhas entre saves
    lines_since_save = 0

    # 1. Escanear os arquivos do projeto antes da execução
    def scan_files(dir_path):
        files_map = {}
        for root, dirs, files in os.walk(dir_path):
            if any(ignored in root.replace("\\", "/").split("/") for ignored in (".git", "node_modules", ".mimocode")):
                continue
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.relpath(abs_path, dir_path).replace("\\", "/")
                try:
                    files_map[rel_path] = os.path.getmtime(abs_path)
                except Exception:
                    pass
        return files_map

    pre_files = await asyncio.to_thread(scan_files, project_path)

    try:
        async for line in mimo_run_fn(project_path, prompt):
            state.output_lines.append(line)
            lines_since_save += 1

            # Notificar subscribers
            await _notify_subscribers(state, {
                "type": "output",
                "line": line,
                "line_idx": len(state.output_lines) - 1,
                "run_id": run_id,
                "elapsed": state.elapsed,
            })

            # Salvar progresso periodicamente
            if lines_since_save >= save_interval:
                await _save_progress(state)
                lines_since_save = 0

        state.status = "success"

    except asyncio.CancelledError:
        state.status = "cancelled"
    except Exception as e:
        state.status = "error"
        await _notify_subscribers(state, {
            "type": "error",
            "message": str(e),
            "run_id": run_id,
        })
    finally:
        # Detectar mudanças no sistema de arquivos comparando com o scan inicial
        def get_changes(pre, dir_path):
            post = scan_files(dir_path)
            changed = []
            for rel_path, post_mtime in post.items():
                if rel_path not in pre or pre[rel_path] != post_mtime:
                    changed.append(rel_path)
            for rel_path in pre.keys():
                if rel_path not in post:
                    changed.append(rel_path)
            return list(set(changed))

        try:
            state.files_changed = await asyncio.to_thread(get_changes, pre_files, project_path)
        except Exception:
            pass

        # Salvar estado final
        await _save_progress(state)

        # Atualizar status no banco
        try:
            async with AsyncSessionLocal() as session:
                run = await session.get(AntigravityRun, run_id)
                if run:
                    run.status = state.status
                    run.execution_time_s = state.elapsed
                    run.output_log = state.output_log
                    run.files_changed = json.dumps(state.files_changed) if state.files_changed else None
                    run.finished_at = datetime.now(timezone.utc)
                    await session.commit()
        except Exception:
            pass

        # Notificar conclusão
        await _notify_subscribers(state, {
            "type": "done",
            "run_id": run_id,
            "status": state.status,
            "elapsed": state.elapsed,
            "files_changed": state.files_changed,
        })

        # Limpar após 5 minutos
        await asyncio.sleep(300)
        _active_runs.pop(run_id, None)


async def subscribe_run(run_id: int, last_line_idx: int = -1) -> AsyncGenerator[dict, None]:
    """Permite ao frontend se inscrever nos eventos de um run ativo."""
    state = _active_runs.get(run_id)
    if not state:
        return

    queue: asyncio.Queue = asyncio.Queue(maxsize=100)
    state.subscribers.append(queue)

    try:
        # Enviar logs perdidos/anteriores a partir do last_line_idx + 1
        start_idx = last_line_idx + 1
        if start_idx < len(state.output_lines):
            for idx in range(start_idx, len(state.output_lines)):
                yield {
                    "type": "output",
                    "line": state.output_lines[idx],
                    "line_idx": idx,
                    "run_id": run_id,
                    "elapsed": state.elapsed,
                }
                last_line_idx = idx

        while True:
            try:
                event = await asyncio.wait_for(queue.get(), timeout=30)
                if event.get("type") == "output":
                    line_idx = event.get("line_idx", -1)
                    if line_idx <= last_line_idx:
                        continue
                    last_line_idx = line_idx

                yield event
                if event.get("type") == "done":
                    break
            except asyncio.TimeoutError:
                # Heartbeat para manter conexão viva
                yield {"type": "heartbeat", "elapsed": state.elapsed}
    finally:
        if queue in state.subscribers:
            state.subscribers.remove(queue)
