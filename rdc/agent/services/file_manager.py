"""
RDC Agent — Serviço de Arquivos
Suporte a projetos grandes com carregamento incremental por diretório.
"""
from __future__ import annotations

import mimetypes
import os
import shutil
from pathlib import Path

import aiofiles

from schemas.files import FileNode

# Extensões ignoradas (node_modules, caches, etc.)
IGNORED_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv", "env",
    ".mypy_cache", ".pytest_cache", "dist", "build", ".next", ".nuxt",
    "target", "out", ".dart_tool", ".flutter-plugins",
}

LANGUAGE_MAP = {
    ".py": "python", ".js": "javascript", ".ts": "typescript",
    ".jsx": "jsx", ".tsx": "tsx", ".html": "html", ".css": "css",
    ".scss": "scss", ".json": "json", ".yaml": "yaml", ".yml": "yaml",
    ".md": "markdown", ".rs": "rust", ".go": "go", ".c": "c",
    ".cpp": "cpp", ".h": "c", ".java": "java", ".kt": "kotlin",
    ".dart": "dart", ".sh": "bash", ".ps1": "powershell",
    ".toml": "toml", ".xml": "xml", ".sql": "sql",
}


def _ext_lang(path: str) -> str | None:
    return LANGUAGE_MAP.get(Path(path).suffix.lower())


def list_directory(project_path: str, relative: str = "") -> list[FileNode]:
    """
    Retorna os filhos imediatos de um diretório (não recursivo).
    Usado para carregamento incremental no explorador.
    """
    base = Path(project_path)
    target = base / relative if relative else base
    target = target.resolve()

    # Segurança: não sair do projeto
    if not str(target).startswith(str(base.resolve())):
        raise PermissionError("Acesso negado: fora do projeto")

    nodes: list[FileNode] = []
    try:
        entries = sorted(target.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
    except PermissionError:
        return []

    for entry in entries:
        if entry.name.startswith(".") and entry.name in IGNORED_DIRS:
            continue
        if entry.is_dir() and entry.name in IGNORED_DIRS:
            continue

        rel = str(entry.relative_to(base)).replace("\\", "/")
        nodes.append(
            FileNode(
                name=entry.name,
                path=rel,
                is_dir=entry.is_dir(),
                size=entry.stat().st_size if entry.is_file() else None,
                extension=entry.suffix.lower() if entry.is_file() else None,
            )
        )
    return nodes


async def read_file(project_path: str, relative: str) -> tuple[str, str | None]:
    """Lê o conteúdo de um arquivo. Retorna (conteúdo, linguagem)."""
    target = _resolve_safe(project_path, relative)
    async with aiofiles.open(target, "r", encoding="utf-8", errors="replace") as f:
        content = await f.read()
    return content, _ext_lang(relative)


async def write_file(project_path: str, relative: str, content: str) -> None:
    """Escreve conteúdo em um arquivo existente."""
    target = _resolve_safe(project_path, relative)
    async with aiofiles.open(target, "w", encoding="utf-8") as f:
        await f.write(content)


def create_file(project_path: str, relative: str, is_dir: bool = False) -> None:
    """Cria arquivo ou diretório."""
    target = _resolve_safe(project_path, relative)
    if is_dir:
        target.mkdir(parents=True, exist_ok=True)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.touch(exist_ok=True)


def rename_path(project_path: str, old_rel: str, new_rel: str) -> None:
    src = _resolve_safe(project_path, old_rel)
    dst = _resolve_safe(project_path, new_rel)
    src.rename(dst)


def delete_path(project_path: str, relative: str) -> None:
    target = _resolve_safe(project_path, relative)
    if target.is_dir():
        shutil.rmtree(target)
    else:
        target.unlink()


def copy_path(project_path: str, src_rel: str, dst_rel: str) -> None:
    src = _resolve_safe(project_path, src_rel)
    dst = _resolve_safe(project_path, dst_rel)
    if src.is_dir():
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)


async def save_upload(project_path: str, relative_dir: str, filename: str, data: bytes) -> str:
    """Salva um arquivo de upload no diretório especificado."""
    target_dir = _resolve_safe(project_path, relative_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / filename
    async with aiofiles.open(target, "wb") as f:
        await f.write(data)
    rel = str(target.relative_to(Path(project_path))).replace("\\", "/")
    return rel


def _resolve_safe(project_path: str, relative: str) -> Path:
    base = Path(project_path).resolve()
    target = (base / relative).resolve()
    if not str(target).startswith(str(base)):
        raise PermissionError("Acesso negado: caminho fora do projeto")
    return target
