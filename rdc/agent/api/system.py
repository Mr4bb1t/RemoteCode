"""
RDC Agent — System API: GET /api/system
"""
from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, Depends

from auth.middleware import get_current_user
from schemas.system import SystemInfo
from services.system_info import get_system_info

router = APIRouter(prefix="/api/system", tags=["System"])


@router.get("", response_model=SystemInfo)
def read_system(_: dict = Depends(get_current_user)) -> SystemInfo:
    return get_system_info()


@router.get("/browse")
def browse_system(path: str = "", _: dict = Depends(get_current_user)) -> list[dict]:
    res = []
    if not path:
        import platform
        if platform.system() == "Windows":
            import string
            from ctypes import windll
            drives = []
            bitmask = windll.kernel32.GetLogicalDrives()
            for letter in string.ascii_uppercase:
                if bitmask & 1:
                    drives.append(f"{letter}:\\")
                bitmask >>= 1
            for d in drives:
                res.append({"name": d, "path": d, "is_dir": True})
            return res
        else:
            path = "/"
            
    p = Path(path)
    if not p.exists() or not p.is_dir():
        return []
    
    if str(p) != str(p.parent):
        res.append({"name": "..", "path": str(p.parent), "is_dir": True})
        
    try:
        for child in p.iterdir():
            if child.is_dir():
                res.append({"name": child.name, "path": str(child), "is_dir": True})
    except PermissionError:
        pass
        
    res.sort(key=lambda x: x["name"].lower() if x["name"] != ".." else "")
    return res
