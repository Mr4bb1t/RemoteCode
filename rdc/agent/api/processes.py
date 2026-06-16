from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from auth.middleware import get_current_user
from database import get_db
from models.project import Project
from services.process_manager import start_process, kill_process

router = APIRouter(prefix="/api/processes", tags=["Processes"])

class ProcessStartRequest(BaseModel):
    process_id: str
    command: list[str]
    cwd: str
    project_id: int

@router.post("/start")
async def api_start_process(req: ProcessStartRequest, db: AsyncSession = Depends(get_db), _: dict = Depends(get_current_user)):
    cwd = req.cwd
    if not cwd and req.project_id:
        result = await db.execute(select(Project).where(Project.id == req.project_id))
        project = result.scalar_one_or_none()
        if project:
            cwd = project.path

    try:
        mp = await start_process(req.process_id, req.command, cwd)
        return {"status": "ok", "process_id": mp.process_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/stop/{process_id}")
async def api_stop_process(process_id: str, _: dict = Depends(get_current_user)):
    success = kill_process(process_id)
    return {"status": "ok", "success": success}
