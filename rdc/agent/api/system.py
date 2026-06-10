"""
RDC Agent — System API: GET /api/system
"""
from __future__ import annotations

from fastapi import APIRouter, Depends

from auth.middleware import get_current_user
from schemas.system import SystemInfo
from services.system_info import get_system_info

router = APIRouter(prefix="/api/system", tags=["System"])


@router.get("", response_model=SystemInfo)
def read_system(_: dict = Depends(get_current_user)) -> SystemInfo:
    return get_system_info()
