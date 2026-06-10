"""
RDC Agent — Serviço Antigravity CLI
Executa o Antigravity CLI como subprocess e captura output em tempo real.
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import AsyncGenerator

from config import get_settings
from services.process_manager import run_and_collect

settings = get_settings()


async def run_prompt(
    project_path: str,
    prompt: str,
) -> AsyncGenerator[str, None]:
    """
    Executa o Antigravity CLI com o prompt fornecido.
    Gera linhas de output em tempo real via async generator.
    """
    cmd = [settings.antigravity_command, prompt]
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=project_path,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        env=env,
    )

    assert proc.stdout is not None
    while True:
        line = await proc.stdout.readline()
        if not line:
            break
        yield line.decode("utf-8", errors="replace")

    await proc.wait()


async def run_prompt_collect(project_path: str, prompt: str) -> tuple[str, int]:
    """Executa o Antigravity e coleta todo o output."""
    output, code = await run_and_collect(
        [settings.antigravity_command, prompt],
        cwd=project_path,
        timeout=600,
    )
    return output, code


def detect_changed_files(project_path: str, output_log: str) -> list[str]:
    """
    Tenta extrair a lista de arquivos modificados do output do Antigravity.
    Estratégia simples: busca linhas que contenham caminhos de arquivo.
    """
    changed: list[str] = []
    base = Path(project_path).resolve()

    for line in output_log.splitlines():
        line = line.strip()
        # Padrões comuns no output do Antigravity
        for prefix in ("Modified:", "Created:", "Deleted:", "  + ", "  ~ ", "  - "):
            if line.startswith(prefix):
                candidate = line[len(prefix):].strip()
                # Normalizar separadores
                candidate = candidate.replace("\\", "/")
                if candidate and not candidate.startswith(("http", "#")):
                    changed.append(candidate)
                break

    return changed
