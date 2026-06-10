"""
RDC Agent — JWT + Refresh Token
"""
from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from config import get_settings

settings = get_settings()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

ALGORITHM = settings.algorithm
SECRET_KEY = settings.secret_key


# ── Senha ────────────────────────────────────────────────────────────────────

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def hash_password(plain: str) -> str:
    return pwd_context.hash(plain)


def verify_agent_password(plain: str) -> bool:
    """Verifica senha direta (sem hash) do agente."""
    return plain == settings.agent_password


# ── Access Token ─────────────────────────────────────────────────────────────

def create_access_token(data: dict | None = None) -> str:
    payload = data.copy() if data else {}
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload.update({"exp": expire, "type": "access"})
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    """Decodifica e valida access token. Lança JWTError se inválido."""
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    if payload.get("type") != "access":
        raise JWTError("Token type mismatch")
    return payload


# ── Refresh Token ─────────────────────────────────────────────────────────────

def create_refresh_token() -> tuple[str, str, datetime]:
    """
    Retorna:
        raw_token   — enviado ao cliente
        token_hash  — armazenado no banco
        expires_at  — datetime de expiração
    """
    raw = secrets.token_urlsafe(64)
    token_hash = hashlib.sha256(raw.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_expire_days
    )
    return raw, token_hash, expires_at


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()
