"""
RDC Agent — Settings API
Permite que o app mobile atualize configurações do agente (modelo de IA, chave).
"""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from auth.middleware import get_current_user
from config import get_settings

router = APIRouter(prefix="/api/settings", tags=["Settings"])

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"


class AiSettingsRequest(BaseModel):
    ai_model: str
    ai_api_key: str


@router.post("/ai")
async def update_ai_settings(
    body: AiSettingsRequest,
    _: dict = Depends(get_current_user),
) -> dict:
    """Atualiza AI_MODEL e AI_API_KEY no .env e nas configurações em tempo real."""
    try:
        from dotenv import set_key
        set_key(str(ENV_PATH), "AI_MODEL",   body.ai_model)
        set_key(str(ENV_PATH), "AI_API_KEY", body.ai_api_key)
    except Exception:
        pass

    # Atualiza os valores em runtime sem precisar reiniciar o servidor
    os.environ["AI_MODEL"]   = body.ai_model
    os.environ["AI_API_KEY"] = body.ai_api_key

    # Limpa o cache de settings para pegar os novos valores
    get_settings.cache_clear()

    return {"message": "Configurações de IA atualizadas", "model": body.ai_model}


@router.get("/ai")
async def get_ai_settings(
    _: dict = Depends(get_current_user),
) -> dict:
    """Retorna o modelo de IA atual configurado no agente."""
    settings = get_settings()
    return {
        "ai_model": settings.ai_model,
        "has_key":  bool(settings.ai_api_key),
    }
