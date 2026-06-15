"""
RDC Agent — Scanner de portas abertas (detectar servidores dev)
"""
from __future__ import annotations

import asyncio
import socket
from dataclasses import dataclass

from config import get_settings

settings = get_settings()

# Mapeamento de portas conhecidas → framework
KNOWN_DEV_PORTS: dict[int, str] = {
    3000: "React / Next.js / Express",
    3001: "React (alt)",
    4200: "Angular",
    4321: "Astro",
    5000: "Flask / Python",
    5173: "Vite",
    5174: "Vite (alt)",
    6006: "Storybook",
    7860: "Gradio",
    8000: "FastAPI / Django / Python",
    8080: "Servidor genérico",
    8081: "React Native Metro",
    8888: "Jupyter",
    9000: "PHP / misc",
    9001: "misc",
}


@dataclass
class OpenPort:
    port: int
    framework_hint: str | None = None
    pid: int | None = None


async def _check_port(port: int) -> bool:
    """Verifica se uma porta está aberta em localhost."""
    loop = asyncio.get_event_loop()
    try:
        conn = asyncio.open_connection("127.0.0.1", port)
        reader, writer = await asyncio.wait_for(conn, timeout=0.2)
        writer.close()
        await writer.wait_closed()
        return True
    except (ConnectionRefusedError, asyncio.TimeoutError, OSError):
        return False


async def scan_open_ports(
    start: int | None = None,
    end: int | None = None,
) -> list[OpenPort]:
    """
    Escaneia portas em localhost no range configurado.
    Prioriza portas conhecidas de frameworks de desenvolvimento.
    """
    start = start or settings.scan_port_range_start
    end = end or settings.scan_port_range_end

    # Verificar portas conhecidas primeiro (mais rápido)
    known_open: list[OpenPort] = []
    tasks_known = {
        port: asyncio.create_task(_check_port(port))
        for port in KNOWN_DEV_PORTS
        if start <= port <= end
    }
    for port, task in tasks_known.items():
        if await task:
            known_open.append(
                OpenPort(port=port, framework_hint=KNOWN_DEV_PORTS[port])
            )

    # Scan de portas adicionais em batches
    extra_ports = [p for p in range(start, end + 1) if p not in KNOWN_DEV_PORTS]
    batch_size = 100
    extra_open: list[OpenPort] = []

    for i in range(0, len(extra_ports), batch_size):
        batch = extra_ports[i : i + batch_size]
        results = await asyncio.gather(*[_check_port(p) for p in batch])
        for port, is_open in zip(batch, results):
            if is_open:
                extra_open.append(OpenPort(port=port))

    all_open = sorted(known_open + extra_open, key=lambda p: p.port)
    return all_open
