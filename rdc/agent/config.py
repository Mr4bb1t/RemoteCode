"""
RDC Agent — Configurações
"""
from __future__ import annotations

import secrets
from pathlib import Path
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Servidor ────────────────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8765
    debug: bool = False

    # ── Segurança ────────────────────────────────────────────────────────────
    secret_key: str = secrets.token_hex(32)
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30

    # Senha do agente (configurada pelo usuário no .env)
    agent_password: str = "rdc_change_me"

    # ── Banco de dados ───────────────────────────────────────────────────────
    database_url: str = f"sqlite+aiosqlite:///{BASE_DIR / 'rdc.db'}"

    # ── TLS ─────────────────────────────────────────────────────────────────
    ssl_certfile: Path = BASE_DIR / "certs" / "cert.pem"
    ssl_keyfile: Path = BASE_DIR / "certs" / "key.pem"

    # ── Antigravity (AI Agent) ──────────────────────────────────────────────
    ai_model: str = "gemini/gemini-2.5-flash"  # Padrão litellm para o Gemini
    ai_api_key: str = ""

    # ── Preview Proxy ────────────────────────────────────────────────────────
    proxy_base_path: str = "/proxy"
    scan_port_range_start: int = 3000
    scan_port_range_end: int = 9999

    # ── Arquivos ─────────────────────────────────────────────────────────────
    max_file_size_mb: int = 50
    max_upload_size_mb: int = 100

    # ── CORS ─────────────────────────────────────────────────────────────────
    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
