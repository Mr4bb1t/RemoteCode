"""
RDC Agent — Preview API: detecção de portas e proxy reverso
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
import httpx
from pydantic import BaseModel

from auth.middleware import get_current_user
from config import get_settings
from services.port_scanner import OpenPort, scan_open_ports

router = APIRouter(prefix="/api/preview", tags=["Preview"])
settings = get_settings()


class PortInfo(BaseModel):
    port: int
    framework_hint: str | None
    url: str  # URL do proxy para este preview


@router.get("/ports", response_model=list[PortInfo])
async def list_open_ports(
    _: dict = Depends(get_current_user),
) -> list[PortInfo]:
    ports = await scan_open_ports()
    return [
        PortInfo(
            port=p.port,
            framework_hint=p.framework_hint,
            url=f"/proxy/{p.port}",
        )
        for p in ports
    ]


# ── Proxy reverso ────────────────────────────────────────────────────────────

_proxy_client = httpx.AsyncClient(verify=False, follow_redirects=True, timeout=30)


async def _proxy_request(request: Request, port: int, path: str) -> Response:
    """Faz proxy de uma request para localhost:<port>/<path>."""
    url = f"http://127.0.0.1:{port}/{path}"
    if request.url.query:
        url += f"?{request.url.query}"

    headers = dict(request.headers)
    headers.pop("host", None)

    body = await request.body()

    try:
        resp = await _proxy_client.request(
            method=request.method,
            url=url,
            headers=headers,
            content=body,
        )
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail=f"Não foi possível conectar na porta {port}")

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        headers=dict(resp.headers),
        media_type=resp.headers.get("content-type"),
    )


@router.api_route("/proxy/{port}/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
async def proxy(port: int, path: str, request: Request) -> Response:
    """
    Proxy reverso sem autenticação (o token é verificado via cookie/header pelo app).
    Redireciona requests para localhost:<port>/<path>.
    """
    return await _proxy_request(request, port, path)


@router.api_route("/proxy/{port}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
async def proxy_root(port: int, request: Request) -> Response:
    return await _proxy_request(request, port, "")
