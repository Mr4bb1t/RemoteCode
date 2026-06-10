"""
RDC Agent — Auth API: /auth/login, /auth/refresh, /auth/logout
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.jwt import (
    create_access_token,
    create_refresh_token,
    hash_refresh_token,
    verify_agent_password,
)
from auth.middleware import get_current_user
from config import get_settings
from database import get_db
from models.session import RefreshSession
from schemas.auth import LoginRequest, MessageResponse, RefreshRequest, TokenResponse

router = APIRouter(prefix="/auth", tags=["Auth"])
settings = get_settings()


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    if not verify_agent_password(body.password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Senha incorreta")

    access_token = create_access_token({"sub": "agent"})
    raw_refresh, token_hash, expires_at = create_refresh_token()

    session = RefreshSession(
        token_hash=token_hash,
        device_info=body.device_info or request.headers.get("user-agent"),
        expires_at=expires_at,
    )
    db.add(session)
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    token_hash = hash_refresh_token(body.refresh_token)
    result = await db.execute(
        select(RefreshSession).where(
            RefreshSession.token_hash == token_hash,
            RefreshSession.is_revoked == False,  # noqa: E712
        )
    )
    session = result.scalar_one_or_none()

    if not session or session.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token inválido ou expirado")

    # Revogar token antigo e criar novo
    session.is_revoked = True

    new_access = create_access_token({"sub": "agent"})
    raw_refresh, new_hash, expires_at = create_refresh_token()

    new_session = RefreshSession(
        token_hash=new_hash,
        device_info=session.device_info,
        expires_at=expires_at,
    )
    db.add(new_session)
    await db.commit()

    return TokenResponse(
        access_token=new_access,
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/logout", response_model=MessageResponse)
async def logout(
    body: RefreshRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    token_hash = hash_refresh_token(body.refresh_token)
    result = await db.execute(
        select(RefreshSession).where(RefreshSession.token_hash == token_hash)
    )
    session = result.scalar_one_or_none()
    if session:
        session.is_revoked = True
        await db.commit()
    return MessageResponse(message="Logout realizado com sucesso")
