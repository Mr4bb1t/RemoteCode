"""
RDC Agent — WebSocket System Monitor
Transmite métricas do sistema em tempo real (polling).

Protocolo:
  GET /ws/system?token=...&interval=2
  Servidor → Cliente: JSON com SystemInfo a cada N segundos
"""
from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from auth.middleware import ws_auth
from services.system_info import get_system_info

router = APIRouter(tags=["WebSocket"])


@router.websocket("/ws/system")
async def system_ws(
    websocket: WebSocket,
    token: str | None = None,
    interval: float = 3.0,
) -> None:
    if not await ws_auth(websocket, token):
        return

    await websocket.accept()
    interval = max(1.0, min(interval, 60.0))  # Entre 1s e 60s

    try:
        while True:
            info = get_system_info()
            await websocket.send_text(info.model_dump_json())
            await asyncio.sleep(interval)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
