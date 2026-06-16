"""
RDC Agent — Gerenciador de Terminal (PTY sessions)
Suporte a CMD, PowerShell e Bash no Windows.
"""
from __future__ import annotations

import asyncio
import os
import platform
import sys
from dataclasses import dataclass, field
from typing import Callable

IS_WINDOWS = platform.system() == "Windows"

if IS_WINDOWS:
    import winpty  # pywinpty

_sessions: dict[str, "TerminalSession"] = {}


@dataclass
class TerminalSession:
    session_id: str
    shell: str
    cwd: str
    process: object = field(default=None, repr=False)
    history: list[str] = field(default_factory=list)
    alive: bool = True


def create_session(session_id: str, shell: str = "auto", cwd: str | None = None) -> TerminalSession:
    """Cria uma nova sessão PTY."""
    if session_id in _sessions and _sessions[session_id].alive:
        return _sessions[session_id]

    cwd = cwd or os.path.expanduser("~")
    shell_cmd = _resolve_shell(shell)

    if IS_WINDOWS:
        proc = winpty.PtyProcess.spawn(shell_cmd, cwd=cwd)
    else:
        import pty
        # Não implementado nesta versão (foco em Windows)
        raise NotImplementedError("PTY nativo em Linux não suportado nesta versão")

    session = TerminalSession(
        session_id=session_id,
        shell=shell_cmd,
        cwd=cwd,
        process=proc,
    )
    _sessions[session_id] = session
    return session


def get_session(session_id: str) -> TerminalSession | None:
    return _sessions.get(session_id)


def kill_session(session_id: str) -> None:
    session = _sessions.pop(session_id, None)
    if session and session.process:
        try:
            if IS_WINDOWS:
                session.process.close()
        except Exception:
            pass
    if session:
        session.alive = False

def kill_all_sessions() -> None:
    session_ids = list(_sessions.keys())
    for sid in session_ids:
        kill_session(sid)


def write_to_session(session_id: str, data: str) -> None:
    session = _sessions.get(session_id)
    if session and session.alive and session.process:
        if IS_WINDOWS:
            session.process.write(data)
        session.history.append(data)


def read_from_session(session_id: str) -> str | None:
    session = _sessions.get(session_id)
    if not session or not session.alive:
        return None
    try:
        if IS_WINDOWS:
            return session.process.read(65536)
    except Exception:
        session.alive = False
        return None
    return None


def resize_session(session_id: str, cols: int, rows: int) -> None:
    session = _sessions.get(session_id)
    if session and session.alive and session.process:
        try:
            if IS_WINDOWS:
                session.process.setwinsize(rows, cols)
        except Exception:
            pass


def _resolve_shell(shell: str) -> str:
    if shell == "auto" or not shell:
        if IS_WINDOWS:
            return "powershell.exe"
        return "/bin/bash"
    mapping = {
        "powershell": "powershell.exe",
        "cmd": "cmd.exe",
        "bash": "bash.exe" if IS_WINDOWS else "/bin/bash",
    }
    return mapping.get(shell.lower(), shell)


def list_sessions() -> list[dict]:
    return [
        {"session_id": s.session_id, "shell": s.shell, "cwd": s.cwd, "alive": s.alive}
        for s in _sessions.values()
    ]
