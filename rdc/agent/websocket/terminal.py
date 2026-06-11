"""
RDC Agent — WebSocket Terminal
Sessões PTY persistentes via WS. Conecta ao PowerShell/CMD/Bash.

Protocolo:
  Cliente → Servidor: texto (input do teclado) ou JSON {"type":"resize","cols":80,"rows":24}
  Servidor → Cliente: texto (output do terminal com ANSI)
"""
from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from auth.middleware import ws_auth
from services.terminal_manager import (
    create_session,
    kill_session,
    read_from_session,
    resize_session,
    write_to_session,
)

router = APIRouter(tags=["WebSocket"])

READ_INTERVAL = 0.05  # 50ms polling interval


@router.websocket("/ws/terminal/{session_id}")
async def terminal_ws(
    websocket: WebSocket,
    session_id: str,
    token: str | None = None,
    shell: str = "powershell",
    cwd: str | None = None,
) -> None:
    if not await ws_auth(websocket, token):
        return

    await websocket.accept()

    try:
        session = create_session(session_id, shell=shell, cwd=cwd)
    except Exception as e:
        await websocket.send_text(f"\r\n[RDC] Erro ao criar sessão: {e}\r\n")
        await websocket.close()
        return

    await websocket.send_text(f"\r\n[RDC] Sessão {session_id} iniciada ({session.shell})\r\n")

    async def reader():
        """Lê output do PTY e envia ao cliente."""
        while session.alive:
            try:
                # Usa to_thread porque read_from_session (pywinpty.read) é bloqueante
                output = await asyncio.to_thread(read_from_session, session_id)
                if output:
                    await websocket.send_text(output)
                else:
                    await asyncio.sleep(READ_INTERVAL)
            except Exception:
                break

    reader_task = asyncio.create_task(reader())

    try:
        while True:
            data = await websocket.receive_text()
            # Verificar se é um comando de controle (JSON)
            try:
                msg = json.loads(data)
                if msg.get("type") == "resize":
                    resize_session(session_id, msg.get("cols", 80), msg.get("rows", 24))
                elif msg.get("type") == "kill":
                    break
            except (json.JSONDecodeError, TypeError):
                # Texto puro = input do terminal
                write_to_session(session_id, data)
    except WebSocketDisconnect:
        pass
    finally:
        reader_task.cancel()
        # Não matar a sessão para manter persistente
        # kill_session(session_id)


@router.websocket("/ws/terminal/{session_id}/kill")
async def kill_terminal_ws(
    websocket: WebSocket,
    session_id: str,
    token: str | None = None,
) -> None:
    if not await ws_auth(websocket, token):
        return
    await websocket.accept()
    kill_session(session_id)
    await websocket.send_text(f"[RDC] Sessão {session_id} encerrada")
    await websocket.close()
