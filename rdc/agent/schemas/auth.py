"""
Schemas de autenticação
"""
from __future__ import annotations

from pydantic import BaseModel


class LoginRequest(BaseModel):
    password: str
    device_info: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # segundos


class RefreshRequest(BaseModel):
    refresh_token: str


class MessageResponse(BaseModel):
    message: str
