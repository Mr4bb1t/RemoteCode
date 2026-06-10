"""
Schemas de Arquivos
"""
from __future__ import annotations

from pydantic import BaseModel


class FileNode(BaseModel):
    name: str
    path: str  # caminho relativo ao projeto
    is_dir: bool
    size: int | None = None
    extension: str | None = None
    children: list["FileNode"] | None = None  # apenas quando expandido


class FileReadRequest(BaseModel):
    project_id: int
    relative_path: str


class FileReadResponse(BaseModel):
    content: str
    encoding: str = "utf-8"
    size: int
    language: str | None = None


class FileWriteRequest(BaseModel):
    project_id: int
    relative_path: str
    content: str


class FileCreateRequest(BaseModel):
    project_id: int
    relative_path: str
    is_dir: bool = False


class FileRenameRequest(BaseModel):
    project_id: int
    old_path: str
    new_path: str


class FileDeleteRequest(BaseModel):
    project_id: int
    relative_path: str


class FileCopyRequest(BaseModel):
    project_id: int
    source_path: str
    destination_path: str


class MessageResponse(BaseModel):
    message: str
