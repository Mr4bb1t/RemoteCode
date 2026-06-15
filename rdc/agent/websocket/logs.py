"""
RDC Agent — WebSocket Logs
Transmite logs em tempo real de um processo em execução.

Protocolo SSE/WS:
  GET /ws/logs/{process_id}?token=... 
  Servidor → Cliente: linhas de log como texto simples
"""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from auth.middleware import ws_auth
from services.process_manager import get_process, stream_output

router = APIRouter(tags=["WebSocket"])


@router.websocket("/ws/logs/{process_id}")
async def logs_ws(
    websocket: WebSocket,
    process_id: str,
    token: str | None = None,
) -> None:
    if not await ws_auth(websocket, token):
        return

    await websocket.accept()

    mp = get_process(process_id)
    if not mp:
        await websocket.send_text(f"[RDC] Processo '{process_id}' não encontrado")
        await websocket.close()
        return

    # Enviar histórico já acumulado
    for line in mp.output_lines:
        await websocket.send_text(line)

    # Streaming de novas linhas
    try:
        async for line in stream_output(process_id):
            await websocket.send_text(line)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await websocket.send_text(f"\r\n[RDC] Erro: {e}\r\n")
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
