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


def _inject_base_tag(html_content: bytes, port: int) -> bytes:
    try:
        html_str = html_content.decode("utf-8", errors="ignore")
        
        # Reescreve caminhos absolutos (ex: /assets/...) para relativos para usarem a tag <base>
        import re
        html_str = re.sub(r'src=["\']/([^"\']*)["\']', r'src="\1"', html_str)
        html_str = re.sub(r'href=["\']/([^"\']*)["\']', r'href="\1"', html_str)
        
        # Injeta o base tag para que assets relativos usem o path correto com a porta
        base_tag = f'<base href="/api/preview/proxy/{port}/">'
        
        # Tenta inserir logo após <head> ou similar
        head_idx = html_str.lower().find("<head")
        if head_idx != -1:
            end_head_idx = html_str.find(">", head_idx)
            if end_head_idx != -1:
                return (html_str[:end_head_idx + 1] + base_tag + html_str[end_head_idx + 1:]).encode("utf-8")
        
        html_idx = html_str.lower().find("<html")
        if html_idx != -1:
            end_html_idx = html_str.find(">", html_idx)
            if end_html_idx != -1:
                return (html_str[:end_html_idx + 1] + base_tag + html_str[end_html_idx + 1:]).encode("utf-8")
                
        return (base_tag + html_str).encode("utf-8")
    except Exception:
        return html_content


async def _proxy_request(request: Request, port: int, path: str) -> Response:
    """Faz proxy de uma request para localhost:<port>/<path>."""
    url = f"http://localhost:{port}/{path}"
    if request.url.query:
        url += f"?{request.url.query}"

    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("accept-encoding", None)
    headers.pop("authorization", None)

    body = await request.body()

    try:
        resp = await _proxy_client.request(
            method=request.method,
            url=url,
            headers=headers,
            content=body,
        )
    except Exception as e:
        try:
            fallback_url = f"http://127.0.0.1:{port}/{path}"
            if request.url.query:
                fallback_url += f"?{request.url.query}"
            resp = await _proxy_client.request(
                method=request.method,
                url=fallback_url,
                headers=headers,
                content=body,
            )
        except Exception as e2:
            error_html = f"""<!DOCTYPE html>
<html><head><style>
body {{ background: #121212; color: #eee; font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }}
.box {{ text-align: center; padding: 40px; }}
.icon {{ font-size: 48px; margin-bottom: 16px; }}
h2 {{ color: #ff5252; margin-bottom: 8px; }}
p {{ color: #888; font-size: 14px; }}
</style></head><body>
<div class="box">
  <div class="icon">🔌</div>
  <h2>Servidor offline</h2>
  <p>Nenhum servidor rodando na porta <strong>{port}</strong></p>
  <p>Erro ao conectar: {e2}</p>
</div>
</body></html>"""
            return Response(content=error_html.encode(), status_code=200, media_type="text/html")

    resp_headers = dict(resp.headers)
    resp_headers.pop("content-encoding", None)
    resp_headers.pop("content-length", None)
    resp_headers.pop("transfer-encoding", None)

    content = resp.content
    media_type = resp.headers.get("content-type", "")
    if media_type and "text/html" in media_type:
        content = _inject_base_tag(content, port)

    fastapi_resp = Response(
        content=content,
        status_code=resp.status_code,
        headers=resp_headers,
        media_type=media_type if media_type else None,
    )
    
    is_secure = request.url.scheme == "https"
    fastapi_resp.set_cookie(
        "rdc_preview_port",
        str(port),
        path="/",
        secure=is_secure,
        samesite="none" if is_secure else "lax",
        httponly=False,
    )
    
    # Propaga o token de autorização como cookie rdc_token para os sub-recursos
    auth_header = request.headers.get("authorization")
    token = None
    if auth_header and auth_header.lower().startswith("bearer "):
        token = auth_header[7:]
    else:
        token = request.query_params.get("token")
        
    if token:
        fastapi_resp.set_cookie(
            "rdc_token",
            token,
            path="/",
            secure=is_secure,
            samesite="none" if is_secure else "lax",
            httponly=False,
        )
        
    return fastapi_resp


@router.api_route("/proxy/{port}/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
async def proxy(port: int, path: str, request: Request) -> Response:
    """
    Proxy reverso sem autenticação (o token é verificado via cookie/header pelo app).
    Redireciona requests para localhost:<port>/<path>.
    """
    return await _proxy_request(request, port, path)


@router.api_route("/proxy/{port}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
async def proxy_root(port: int, request: Request) -> Response:
    from fastapi.responses import RedirectResponse
    target_url = str(request.url)
    if not target_url.endswith("/"):
        return RedirectResponse(url=target_url + "/")
    return await _proxy_request(request, port, "")
