"""
RDC Agent — Entry Point
Remote Dev Control: Agente Desktop para desenvolvimento remoto via dispositivo móvel.

Uso:
    python main.py          # Inicia com HTTPS (certificado auto-assinado)
    python main.py --http   # Inicia apenas HTTP (desenvolvimento local)
"""
from __future__ import annotations

import argparse
import asyncio
import socket
import sys

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

from api.router import router as api_router
from config import get_settings
from database import init_db
from services.tls_service import ensure_tls_cert
from websocket.logs import router as logs_ws_router
from websocket.system import router as system_ws_router
from websocket.terminal import router as terminal_ws_router

settings = get_settings()

# ── Aplicação FastAPI ─────────────────────────────────────────────────────────

app = FastAPI(
    title="RDC Agent",
    description="Remote Dev Control — Agente Desktop",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS — permite qualquer origem (o app mobile conecta de IPs variados)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rotas
app.include_router(api_router)
app.include_router(terminal_ws_router)
app.include_router(logs_ws_router)
app.include_router(system_ws_router)


# ── Startup / Shutdown ────────────────────────────────────────────────────────

@app.on_event("startup")
async def on_startup() -> None:
    await init_db()
    print("[RDC] Banco de dados inicializado")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    print("[RDC] Encerrando agente...")


# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/health", tags=["Health"])
def health() -> dict:
    return {"status": "ok", "version": "1.0.0"}


# ── Main ──────────────────────────────────────────────────────────────────────

def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def main() -> None:
    parser = argparse.ArgumentParser(description="RDC Agent")
    parser.add_argument("--http", action="store_true", help="Usar HTTP em vez de HTTPS")
    parser.add_argument("--host", default=settings.host, help="Host de escuta")
    parser.add_argument("--port", type=int, default=settings.port, help="Porta")
    parser.add_argument("--password", help="Sobrescrever senha do agente")
    parser.add_argument("--cli", action="store_true", help="Inicia em modo texto (sem interface gráfica)")
    args = parser.parse_args()

    # Se não foi pedido modo CLI, tenta carregar a Interface Gráfica
    if not args.cli:
        try:
            import gui
            gui.start_gui()
            return
        except Exception as e:
            print(f"[RDC] Erro ao carregar interface gráfica: {e}")
            print("[RDC] Iniciando em modo CLI...")

    if args.password:
        settings.agent_password = args.password

    local_ip = get_local_ip()
    use_https = not args.http

    if use_https:
        ensure_tls_cert(settings.ssl_certfile, settings.ssl_keyfile)

    protocol = "https" if use_https else "http"
    ws_protocol = "wss" if use_https else "ws"

    print("\n" + "=" * 60)
    print("  [RDC] Agent -- Remote Dev Control")
    print("=" * 60)
    print(f"  Endereço local:   {protocol}://{local_ip}:{args.port}")
    print(f"  WebSocket:        {ws_protocol}://{local_ip}:{args.port}/ws/...")
    print(f"  Documentação:     {protocol}://{local_ip}:{args.port}/docs")
    print(f"  Senha:            {'(configurada)' if settings.agent_password != 'rdc_change_me' else '[AVISO] PADRAO - altere no .env!'}")
    if use_https:
        print(f"  TLS:              Certificado auto-assinado")
        print(f"  [AVISO] Aceite o certificado no seu dispositivo movel")
    print("=" * 60 + "\n")

    uvicorn_kwargs = dict(
        app="main:app",
        host=args.host,
        port=args.port,
        reload=settings.debug,
        log_level="info",
    )

    if use_https:
        uvicorn_kwargs["ssl_certfile"] = str(settings.ssl_certfile)
        uvicorn_kwargs["ssl_keyfile"] = str(settings.ssl_keyfile)

    uvicorn.run(**uvicorn_kwargs)


if __name__ == "__main__":
    main()
