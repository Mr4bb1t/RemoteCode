"""
RDC Agent — Auth Middleware (FastAPI Dependency)
"""
from __future__ import annotations

from fastapi import Depends, HTTPException, WebSocket, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError

from auth.jwt import decode_access_token

bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> dict:
    """
    Dependency para rotas HTTP protegidas.
    Retorna o payload do JWT se válido.
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token não fornecido",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = decode_access_token(credentials.credentials)
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
