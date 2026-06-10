"""
RDC Agent — API Router (agrega todas as rotas)
"""
from __future__ import annotations

from fastapi import APIRouter

from api.auth import router as auth_router
from api.system import router as system_router
from api.projects import router as projects_router
from api.files import router as files_router
from api.git import router as git_router
from api.tests import router as tests_router
from api.preview import router as preview_router
from api.antigravity import router as antigravity_router

router = APIRouter()

router.include_router(auth_router)
router.include_router(system_router)
router.include_router(projects_router)
router.include_router(files_router)
router.include_router(git_router)
router.include_router(tests_router)
router.include_router(preview_router)
router.include_router(antigravity_router)
