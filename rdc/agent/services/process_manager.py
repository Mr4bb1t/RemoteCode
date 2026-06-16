"""
RDC Agent — Gerenciador de processos e captura de logs em tempo real
"""
from __future__ import annotations

import asyncio
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import AsyncGenerator

_processes: dict[str, "ManagedProcess"] = {}


@dataclass
class ManagedProcess:
    process_id: str
    command: str
    cwd: str
    process: asyncio.subprocess.Process | None = field(default=None, repr=False)
    output_lines: list[str] = field(default_factory=list)
    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    finished_at: datetime | None = None
    return_code: int | None = None

    @property
    def is_running(self) -> bool:
        return self.process is not None and self.process.returncode is None


async def start_process(
    process_id: str,
    command: list[str],
    cwd: str,
) -> "ManagedProcess":
    """Inicia um processo e registra."""
    import platform
    is_windows = platform.system() == "Windows"
    
    if is_windows:
        # No Windows, usar shell=True permite encontrar comandos como 'npm' ou 'flutter' sem .cmd
        proc = await asyncio.create_subprocess_shell(
            " ".join(command),
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    else:
        proc = await asyncio.create_subprocess_exec(
            *command,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    mp = ManagedProcess(process_id=process_id, command=" ".join(command), cwd=cwd, process=proc)
    _processes[process_id] = mp
    return mp


async def stream_output(process_id: str) -> AsyncGenerator[str, None]:
    """Gerador que emite linhas de output do processo em tempo real."""
    mp = _processes.get(process_id)
    if not mp or not mp.process:
        return

    assert mp.process.stdout is not None
    while True:
        line = await mp.process.stdout.readline()
        if not line:
            break
        decoded = line.decode("utf-8", errors="replace")
        mp.output_lines.append(decoded)
        yield decoded

    await mp.process.wait()
    mp.return_code = mp.process.returncode
    mp.finished_at = datetime.now(timezone.utc)


async def run_and_collect(command: list[str], cwd: str, timeout: int = 300) -> tuple[str, int]:
    """Executa um comando e coleta todo o output. Retorna (output, returncode)."""
    proc = None
    try:
        proc = await asyncio.wait_for(
            asyncio.create_subprocess_exec(
                *command,
                cwd=cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            ),
            timeout=5,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode("utf-8", errors="replace"), proc.returncode or 0
    except asyncio.TimeoutError:
        return "Timeout excedido", 1
    except Exception as e:
        return str(e), 1
    finally:
        if proc and proc.returncode is None:
            try:
                proc.kill()
            except Exception:
                pass


def kill_process(process_id: str) -> bool:
    mp = _processes.get(process_id)
    if mp and mp.process:
        try:
            import platform
            if platform.system() == "Windows":
                import subprocess
                res = subprocess.run(["taskkill", "/F", "/T", "/PID", str(mp.process.pid)], capture_output=True, text=True)
                print(f"[RDC] taskkill output: {res.stdout} {res.stderr}")
                try:
                    mp.process.terminate()
                except Exception:
                    pass
            else:
                mp.process.terminate()
            return True
        except Exception as e:
            print(f"[RDC] Erro ao matar processo: {e}")
            return False
    return False

def kill_all_processes() -> None:
    import platform
    is_windows = platform.system() == "Windows"
    for mp in _processes.values():
        if mp.is_running and mp.process:
            try:
                if is_windows:
                    import subprocess
                    subprocess.run(["taskkill", "/F", "/T", "/PID", str(mp.process.pid)], capture_output=True)
                else:
                    mp.process.terminate()
            except Exception:
                pass


def get_process(process_id: str) -> ManagedProcess | None:
    return _processes.get(process_id)


def list_processes() -> list[dict]:
    return [
        {
            "process_id": p.process_id,
            "command": p.command,
            "cwd": p.cwd,
            "is_running": p.is_running,
            "started_at": p.started_at.isoformat(),
            "return_code": p.return_code,
        }
        for p in _processes.values()
    ]
