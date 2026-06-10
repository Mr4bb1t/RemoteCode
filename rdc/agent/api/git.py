"""
RDC Agent — Git API
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from database import get_db
from models.project import Project
from schemas.git import (
    GitBranchCreate,
    GitBranchList,
    GitCheckoutRequest,
    GitCommitRequest,
    GitDiffResponse,
    GitLogResponse,
    GitOperationResult,
    GitPullRequest,
    GitPushRequest,
    GitStatusResponse,
)
from services import git_service

router = APIRouter(prefix="/api/git", tags=["Git"])


async def _project_path(project_id: int, db: AsyncSession) -> str:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")
    return project.path


@router.get("/{project_id}/status", response_model=GitStatusResponse)
async def git_status(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitStatusResponse:
    path = await _project_path(project_id, db)
    try:
        return git_service.get_status(path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{project_id}/log", response_model=GitLogResponse)
async def git_log(
    project_id: int,
    limit: int = Query(default=50, le=200),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitLogResponse:
    path = await _project_path(project_id, db)
    try:
        return git_service.get_log(path, limit=limit)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{project_id}/diff", response_model=GitDiffResponse)
async def git_diff(
    project_id: int,
    file_path: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitDiffResponse:
    path = await _project_path(project_id, db)
    try:
        return git_service.get_diff(path, file_path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{project_id}/branches", response_model=GitBranchList)
async def git_branches(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitBranchList:
    path = await _project_path(project_id, db)
    try:
        return git_service.list_branches(path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/commit", response_model=GitOperationResult)
async def git_commit(
    project_id: int,
    body: GitCommitRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.commit(path, body.message, body.stage_all, body.files)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/push", response_model=GitOperationResult)
async def git_push(
    project_id: int,
    body: GitPushRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.push(path, body.remote, body.branch)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/pull", response_model=GitOperationResult)
async def git_pull(
    project_id: int,
    body: GitPullRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.pull(path, body.remote, body.branch)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/checkout", response_model=GitOperationResult)
async def git_checkout(
    project_id: int,
    body: GitCheckoutRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.checkout(path, body.branch, body.create)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/branch", response_model=GitOperationResult)
async def git_create_branch(
    project_id: int,
    body: GitBranchCreate,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.create_branch(path, body.name, body.from_branch)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{project_id}/fetch", response_model=GitOperationResult)
async def git_fetch(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> GitOperationResult:
    path = await _project_path(project_id, db)
    try:
        return git_service.fetch(path)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
