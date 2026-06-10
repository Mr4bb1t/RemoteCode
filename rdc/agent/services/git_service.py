"""
RDC Agent — Serviço Git (GitPython wrapper)
"""
from __future__ import annotations

from pathlib import Path

import git
from git import GitCommandError, InvalidGitRepositoryError, Repo

from schemas.git import (
    GitBranchList,
    GitCommit,
    GitDiffResponse,
    GitFileStatus,
    GitLogResponse,
    GitOperationResult,
    GitStatusResponse,
)


def _open_repo(path: str) -> Repo:
    try:
        return Repo(path, search_parent_directories=False)
    except InvalidGitRepositoryError:
        raise ValueError(f"'{path}' não é um repositório Git.")


def get_status(project_path: str) -> GitStatusResponse:
    repo = _open_repo(project_path)
    branch = repo.active_branch.name if not repo.head.is_detached else "HEAD detached"
    tracking = None
    ahead = 0
    behind = 0

    try:
        tracking_branch = repo.active_branch.tracking_branch()
        if tracking_branch:
            tracking = tracking_branch.name
            ahead_commits = list(repo.iter_commits(f"{tracking_branch}..HEAD"))
            behind_commits = list(repo.iter_commits(f"HEAD..{tracking_branch}"))
            ahead = len(ahead_commits)
            behind = len(behind_commits)
    except Exception:
        pass

    modified: list[GitFileStatus] = []
    staged: list[GitFileStatus] = []
    untracked: list[str] = list(repo.untracked_files)

    for item in repo.index.diff(None):  # working tree vs index
        modified.append(GitFileStatus(path=item.a_path, status=item.change_type))

    for item in repo.index.diff("HEAD"):  # index vs HEAD
        staged.append(GitFileStatus(path=item.a_path, status=item.change_type))

    return GitStatusResponse(
        branch=branch,
        tracking=tracking,
        ahead=ahead,
        behind=behind,
        modified=modified,
        staged=staged,
        untracked=untracked,
        is_dirty=repo.is_dirty(untracked_files=True),
    )


def get_log(project_path: str, limit: int = 50) -> GitLogResponse:
    repo = _open_repo(project_path)
    commits: list[GitCommit] = []
    for c in repo.iter_commits(max_count=limit):
        stat = c.stats
        commits.append(
            GitCommit(
                sha=c.hexsha,
                short_sha=c.hexsha[:7],
                message=c.message.strip(),
                author=c.author.name,
                email=c.author.email,
                date=c.authored_datetime.isoformat(),
                files_changed=len(stat.files),
            )
        )
    return GitLogResponse(commits=commits, total=len(commits))


def get_diff(project_path: str, file_path: str | None = None) -> GitDiffResponse:
    repo = _open_repo(project_path)
    try:
        if file_path:
            diff = repo.git.diff("HEAD", "--", file_path)
        else:
            diff = repo.git.diff("HEAD")
    except GitCommandError as e:
        diff = str(e)
    return GitDiffResponse(diff=diff)


def commit(project_path: str, message: str, stage_all: bool = True, files: list[str] | None = None) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        if stage_all:
            repo.git.add("-A")
        elif files:
            repo.index.add(files)
        if not repo.index.diff("HEAD") and not repo.untracked_files:
            return GitOperationResult(success=False, message="Nada para commitar")
        c = repo.index.commit(message)
        return GitOperationResult(success=True, message=f"Commit criado: {c.hexsha[:7]}")
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def push(project_path: str, remote: str = "origin", branch: str | None = None) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        branch = branch or repo.active_branch.name
        result = repo.git.push(remote, branch)
        return GitOperationResult(success=True, message="Push realizado com sucesso", output=result)
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def pull(project_path: str, remote: str = "origin", branch: str | None = None) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        branch = branch or repo.active_branch.name
        result = repo.git.pull(remote, branch)
        return GitOperationResult(success=True, message="Pull realizado com sucesso", output=result)
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def checkout(project_path: str, branch: str, create: bool = False) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        if create:
            repo.git.checkout("-b", branch)
        else:
            repo.git.checkout(branch)
        return GitOperationResult(success=True, message=f"Checkout para '{branch}' realizado")
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def create_branch(project_path: str, name: str, from_branch: str | None = None) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        if from_branch:
            repo.git.branch(name, from_branch)
        else:
            repo.git.branch(name)
        return GitOperationResult(success=True, message=f"Branch '{name}' criada")
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def list_branches(project_path: str) -> GitBranchList:
    repo = _open_repo(project_path)
    local = [b.name for b in repo.branches]
    remote = [r.name for r in repo.remotes[0].refs] if repo.remotes else []
    current = repo.active_branch.name if not repo.head.is_detached else "HEAD"
    return GitBranchList(local=local, remote=remote, current=current)


def fetch(project_path: str) -> GitOperationResult:
    repo = _open_repo(project_path)
    try:
        for remote in repo.remotes:
            remote.fetch()
        return GitOperationResult(success=True, message="Fetch realizado com sucesso")
    except GitCommandError as e:
        return GitOperationResult(success=False, message=str(e))


def get_current_branch(project_path: str) -> str | None:
    try:
        repo = _open_repo(project_path)
        return repo.active_branch.name
    except Exception:
        return None
