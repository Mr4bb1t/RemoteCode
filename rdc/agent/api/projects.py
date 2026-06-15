"""
RDC Agent — Projects API: CRUD + favoritar
"""
from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from database import get_db
from models.project import Project
from schemas.project import ProjectCreate, ProjectResponse, ProjectUpdate
from services.git_service import get_current_branch

router = APIRouter(prefix="/api/projects", tags=["Projects"])


def _enrich(project: Project) -> ProjectResponse:
    """Adiciona dados dinâmicos (branch, last_modified) ao projeto."""
    branch = None
    last_modified = None
    try:
        branch = get_current_branch(project.path)
    except Exception:
        pass
    try:
        p = Path(project.path)
        if p.exists():
            last_modified = p.stat().st_mtime
            import datetime
            last_modified = datetime.datetime.fromtimestamp(last_modified).isoformat()
    except Exception:
        pass

    return ProjectResponse(
        id=project.id,
        name=project.name,
        path=project.path,
        language=project.language,
        description=project.description,
        is_favorite=project.is_favorite,
        current_branch=branch,
        last_modified=last_modified,
        created_at=project.created_at,
        updated_at=project.updated_at,
    )


@router.get("", response_model=list[ProjectResponse])
async def list_projects(
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[ProjectResponse]:
    result = await db.execute(select(Project).order_by(Project.is_favorite.desc(), Project.name))
    projects = result.scalars().all()
    return [_enrich(p) for p in projects]


@router.post("", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(
    body: ProjectCreate,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> ProjectResponse:
    if not Path(body.path).exists():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Caminho não existe: {body.path}",
        )
    existing = await db.execute(select(Project).where(Project.path == body.path))
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Projeto com este caminho já cadastrado",
        )
    project = Project(
        name=body.name,
        path=body.path,
        language=body.language,
        description=body.description,
    )
    db.add(project)
    await db.commit()
    await db.refresh(project)
    return _enrich(project)


@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> ProjectResponse:
    project = await _get_or_404(db, project_id)
    return _enrich(project)


@router.put("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: int,
    body: ProjectUpdate,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> ProjectResponse:
    project = await _get_or_404(db, project_id)
    if body.name is not None:
        project.name = body.name
    if body.language is not None:
        project.language = body.language
    if body.description is not None:
        project.description = body.description
    await db.commit()
    await db.refresh(project)
    return _enrich(project)


@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_project(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> None:
    project = await _get_or_404(db, project_id)
    await db.delete(project)
    await db.commit()


@router.post("/{project_id}/favorite", response_model=ProjectResponse)
async def toggle_favorite(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> ProjectResponse:
    project = await _get_or_404(db, project_id)
    project.is_favorite = not project.is_favorite
    await db.commit()
    await db.refresh(project)
    return _enrich(project)


async def _get_or_404(db: AsyncSession, project_id: int) -> Project:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Projeto não encontrado")
    return project
