"""
RDC Agent — Files API
Navegação incremental, CRUD, upload, download.
"""
from __future__ import annotations

from pathlib import Path

import aiofiles
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from config import get_settings
from database import get_db
from models.project import Project
from schemas.files import (
    FileCopyRequest,
    FileCreateRequest,
    FileDeleteRequest,
    FileNode,
    FileReadResponse,
    FileRenameRequest,
    FileWriteRequest,
    MessageResponse,
)
from services import file_manager

router = APIRouter(prefix="/api/files", tags=["Files"])
settings = get_settings()


async def _project_path(project_id: int, db: AsyncSession) -> str:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")
    return project.path


@router.get("/{project_id}/tree", response_model=list[FileNode])
async def list_tree(
    project_id: int,
    path: str = Query(default="", description="Caminho relativo para listar (vazio = raiz)"),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[FileNode]:
    project_path = await _project_path(project_id, db)
    try:
        return file_manager.list_directory(project_path, path)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.get("/{project_id}/read", response_model=FileReadResponse)
async def read_file(
    project_id: int,
    path: str = Query(..., description="Caminho relativo ao projeto"),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> FileReadResponse:
    project_path = await _project_path(project_id, db)
    try:
        content, language = await file_manager.read_file(project_path, path)
        size = len(content.encode("utf-8"))
        return FileReadResponse(content=content, size=size, language=language)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Arquivo não encontrado")


@router.put("/{project_id}/write", response_model=MessageResponse)
async def write_file(
    project_id: int,
    body: FileWriteRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    try:
        await file_manager.write_file(project_path, body.relative_path, body.content)
        return MessageResponse(message="Arquivo salvo com sucesso")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/{project_id}/create", response_model=MessageResponse, status_code=201)
async def create_file(
    project_id: int,
    body: FileCreateRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    try:
        file_manager.create_file(project_path, body.relative_path, body.is_dir)
        kind = "Pasta" if body.is_dir else "Arquivo"
        return MessageResponse(message=f"{kind} criado com sucesso")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/{project_id}/rename", response_model=MessageResponse)
async def rename(
    project_id: int,
    body: FileRenameRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    try:
        file_manager.rename_path(project_path, body.old_path, body.new_path)
        return MessageResponse(message="Renomeado com sucesso")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.delete("/{project_id}/delete", response_model=MessageResponse)
async def delete_file(
    project_id: int,
    body: FileDeleteRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    try:
        file_manager.delete_path(project_path, body.relative_path)
        return MessageResponse(message="Excluído com sucesso")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/{project_id}/copy", response_model=MessageResponse)
async def copy_file(
    project_id: int,
    body: FileCopyRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    try:
        file_manager.copy_path(project_path, body.source_path, body.destination_path)
        return MessageResponse(message="Copiado com sucesso")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))


@router.post("/{project_id}/upload", response_model=MessageResponse, status_code=201)
async def upload_file(
    project_id: int,
    target_dir: str = Query(default="", description="Diretório de destino"),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> MessageResponse:
    project_path = await _project_path(project_id, db)
    max_bytes = settings.max_upload_size_mb * 1024 * 1024
    data = await file.read()
    if len(data) > max_bytes:
        raise HTTPException(status_code=413, detail=f"Arquivo muito grande (máx {settings.max_upload_size_mb}MB)")
    rel = await file_manager.save_upload(project_path, target_dir, file.filename or "upload", data)
    return MessageResponse(message=f"Upload realizado: {rel}")


@router.get("/{project_id}/download")
async def download_file(
    project_id: int,
    path: str = Query(...),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> FileResponse:
    project_path = await _project_path(project_id, db)
    from pathlib import Path as P
    target = (P(project_path) / path).resolve()
    if not str(target).startswith(str(P(project_path).resolve())):
        raise HTTPException(status_code=403, detail="Acesso negado")
    if not target.is_file():
        raise HTTPException(status_code=404, detail="Arquivo não encontrado")
    return FileResponse(str(target), filename=target.name)
