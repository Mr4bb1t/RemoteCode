"""
Schemas de Git
"""
from __future__ import annotations

from pydantic import BaseModel


class GitFileStatus(BaseModel):
    path: str
    status: str  # modified | added | deleted | untracked | renamed


class GitStatusResponse(BaseModel):
    branch: str
    tracking: str | None
    ahead: int
    behind: int
    modified: list[GitFileStatus]
    staged: list[GitFileStatus]
    untracked: list[str]
    is_dirty: bool


class GitCommit(BaseModel):
    sha: str
    short_sha: str
    message: str
    author: str
    email: str
    date: str
    files_changed: int


class GitLogResponse(BaseModel):
    commits: list[GitCommit]
    total: int


class GitDiffRequest(BaseModel):
    project_id: int
    file_path: str | None = None  # None = diff completo


class GitDiffResponse(BaseModel):
    diff: str


class GitCommitRequest(BaseModel):
    project_id: int
    message: str
    stage_all: bool = True
    files: list[str] | None = None  # arquivos específicos para staged


class GitPushRequest(BaseModel):
    project_id: int
    remote: str = "origin"
    branch: str | None = None  # None = branch atual


class GitPullRequest(BaseModel):
    project_id: int
    remote: str = "origin"
    branch: str | None = None


class GitCheckoutRequest(BaseModel):
    project_id: int
    branch: str
    create: bool = False  # se True, cria a branch


class GitBranchCreate(BaseModel):
    project_id: int
    name: str
    from_branch: str | None = None


class GitBranchList(BaseModel):
    local: list[str]
    remote: list[str]
    current: str


class GitOperationResult(BaseModel):
    success: bool
    message: str
    output: str | None = None
