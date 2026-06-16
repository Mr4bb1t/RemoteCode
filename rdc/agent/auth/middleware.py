"""
RDC Agent — Auth Middleware (FastAPI Dependency)
"""
from __future__ import annotations

from fastapi import Depends, HTTPException, WebSocket, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError

from auth.jwt import decode_access_token

bearer = HTTPBearer(auto_error=False)


from fastapi import Depends, HTTPException, WebSocket, status, Cookie, Query

def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    rdc_token: str | None = Cookie(default=None),
    token: str | None = Query(default=None),
) -> dict:
    """
    Dependency para rotas HTTP protegidas.
    Retorna o payload do JWT se válido.
    Suporta Bearer token, Cookie (rdc_token) e Query parameter (token).
    """
    actual_token = None
    if credentials:
        actual_token = credentials.credentials
    elif rdc_token:
        actual_token = rdc_token
    elif token:
        actual_token = token

    if not actual_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token não fornecido",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = decode_access_token(actual_token)
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido ou expirado",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def ws_auth(websocket: WebSocket, token: str | None = None) -> bool:
    """
    Autentica uma conexão WebSocket.
    O token é passado como query param: ?token=<access_token>
    """
    if not token:
        await websocket.close(code=4001, reason="Token não fornecido")
        return False
    try:
        decode_access_token(token)
        return True
    except JWTError:
        await websocket.close(code=4001, reason="Token inválido")
        return False
