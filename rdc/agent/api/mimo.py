"""
RDC Agent — Mimo API
Executa prompts do MiMo Code, armazena histórico, permite aprovação/rejeição de mudanças,
e lista modelos e ferramentas disponíveis.
Suporta caminhos antigos (/api/antigravity) e novos (/api/mimo).
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from datetime import datetime, timezone
import httpx

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth.middleware import get_current_user
from config import get_settings
from database import get_db, AsyncSessionLocal
from models.antigravity import AntigravityRun
from models.project import Project
from schemas.antigravity import (
    AntigravityApproveRequest,
    AntigravityRunRequest,
    AntigravityRunResponse,
    FileDiff,
)
from services import mimo_service
from services.git_service import get_diff

# APIRouter sem prefixo para permitir múltiplos prefixos por rota
router = APIRouter(tags=["Mimo"])

# Cache em memória para modelos (evita fetch repetido do models.dev)
_models_cache: list[MimoModelInfo] | None = None
_models_cache_ts: float = 0
_MODELS_CACHE_TTL = 300  # 5 minutos

# Schemas para Mimo
class MimoModelInfo(BaseModel):
    id: str
    name: str
    provider: str
    logoAsset: str
    color: str
    keyUrl: str
    keyHint: str
    category: str = "api"  # mimo | popular | local | api
    toolCall: bool = True
    reasoning: bool = False

class MimoFunctionInfo(BaseModel):
    name: str
    description: str

async def _project_path(project_id: int, db: AsyncSession) -> str:
    result = await db.execute(select(Project).where(Project.id == project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")
    return project.path


@router.post("/api/mimo/run")
@router.post("/api/antigravity/run")
async def run_mimo(
    body: AntigravityRunRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> StreamingResponse:
    """
    Executa o MiMo Code em background e faz streaming do output em tempo real (SSE).
    O processo continua rodando mesmo se a conexão cair.
    """
    path = await _project_path(body.project_id, db)

    # Se modelo/chave foram enviados do app, atualiza runtime
    if body.model:
        os.environ["AI_MODEL"] = body.model
        get_settings.cache_clear()
    if body.api_key:
        os.environ["AI_API_KEY"] = body.api_key
        get_settings.cache_clear()

    run = AntigravityRun(
        project_id=body.project_id,
        prompt=body.prompt,
        status="running",
    )
    db.add(run)
    await db.commit()
    await db.refresh(run)
    run_id = run.id

    # Iniciar processo em background
    from services.background_runner import run_in_background, get_active_run, subscribe_run

    task = asyncio.create_task(
        run_in_background(
            run_id=run_id,
            project_path=path,
            prompt=body.prompt,
            mimo_run_fn=mimo_service.run_prompt,
            project_id=body.project_id,
        )
    )

    async def event_generator():
        # Primeiro yield: run_id
        yield f"data: {{\"type\":\"start\",\"run_id\":{run_id}}}\n\n"

        # Inscrever nos eventos do processo em background
        async for event in subscribe_run(run_id):
            event_type = event.get("type")
            if event_type == "output":
                line = event.get("line", "")
                safe = line.replace('"', '\\"').replace("\n", "\\n")
                yield f'data: {{"type":"output","line":"{safe}"}}\n\n'
            elif event_type == "done":
                elapsed = event.get("elapsed", 0)
                files = event.get("files_changed", [])
                fc_json = json.dumps(files)
                yield f'data: {{"type":"done","run_id":{run_id},"elapsed":{elapsed},"files_changed":{fc_json}}}\n\n'
            elif event_type == "error":
                msg = event.get("message", "Erro desconhecido")
                safe_msg = msg.replace('"', '\\"')
                yield f'data: {{"type":"error","message":"{safe_msg}"}}\n\n'
            elif event_type == "heartbeat":
                pass  # mantém conexão viva

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/api/mimo/active")
async def list_active_runs(
    _: dict = Depends(get_current_user),
) -> list[dict]:
    """Lista processos de IA rodando em background."""
    from services.background_runner import get_all_active_runs
    return [s.to_dict() for s in get_all_active_runs()]


@router.get("/api/mimo/run/{run_id}/stream")
async def stream_run(
    run_id: int,
    last_line_idx: int = -1,
    _: dict = Depends(get_current_user),
) -> StreamingResponse:
    """Permite reconectar a um processo em andamento via SSE."""
    from services.background_runner import subscribe_run

    async def event_generator():
        async for event in subscribe_run(run_id, last_line_idx):
            event_type = event.get("type")
            if event_type == "output":
                line = event.get("line", "")
                line_idx = event.get("line_idx", -1)
                safe = line.replace('"', '\\"').replace("\n", "\\n")
                yield f'data: {{"type":"output","line":"{safe}","line_idx":{line_idx}}}\n\n'
            elif event_type == "done":
                elapsed = event.get("elapsed", 0)
                files = event.get("files_changed", [])
                fc_json = json.dumps(files)
                yield f'data: {{"type":"done","run_id":{run_id},"elapsed":{elapsed},"files_changed":{fc_json}}}\n\n'
            elif event_type == "error":
                msg = event.get("message", "Erro")
                safe_msg = msg.replace('"', '\\"')
                yield f'data: {{"type":"error","message":"{safe_msg}"}}\n\n'
            elif event_type == "status":
                yield f'data: {json.dumps(event)}\n\n'
            elif event_type == "heartbeat":
                yield f'data: {{"type":"heartbeat"}}\n\n'

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/api/mimo/history/{project_id}", response_model=list[AntigravityRunResponse])
@router.get("/api/antigravity/history/{project_id}", response_model=list[AntigravityRunResponse])
async def get_history(
    project_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[AntigravityRunResponse]:
    result = await db.execute(
        select(AntigravityRun)
        .where(AntigravityRun.project_id == project_id)
        .order_by(AntigravityRun.created_at.desc())
        .limit(50)
    )
    runs = result.scalars().all()
    
    from services.background_runner import get_active_run
    response_runs = []
    for run in runs:
        active = get_active_run(run.id)
        if active:
            response_runs.append(
                AntigravityRunResponse(
                    id=run.id,
                    project_id=run.project_id,
                    prompt=run.prompt,
                    output_log=active.output_log,
                    status=active.status,
                    files_changed=active.files_changed,
                    execution_time_s=active.elapsed,
                    output_lines_count=len(active.output_lines),
                    created_at=run.created_at,
                    finished_at=run.finished_at,
                )
            )
        else:
            response_runs.append(
                AntigravityRunResponse(
                    **{k: v for k, v in run.__dict__.items() if not k.startswith("_") and k != "files_changed"},
                    files_changed=json.loads(run.files_changed) if run.files_changed else None,
                    output_lines_count=None,
                )
            )
    return response_runs


@router.get("/api/mimo/run/{run_id}", response_model=AntigravityRunResponse)
@router.get("/api/antigravity/run/{run_id}", response_model=AntigravityRunResponse)
async def get_run(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> AntigravityRunResponse:
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")
        
    from services.background_runner import get_active_run
    active = get_active_run(run_id)
    if active:
        return AntigravityRunResponse(
            id=run.id,
            project_id=run.project_id,
            prompt=run.prompt,
            output_log=active.output_log,
            status=active.status,
            files_changed=active.files_changed,
            execution_time_s=active.elapsed,
            output_lines_count=len(active.output_lines),
            created_at=run.created_at,
            finished_at=run.finished_at,
        )
        
    return AntigravityRunResponse(
        **{k: v for k, v in run.__dict__.items() if not k.startswith("_") and k != "files_changed"},
        files_changed=json.loads(run.files_changed) if run.files_changed else None,
        output_lines_count=None,
    )


@router.get("/api/mimo/run/{run_id}/diff", response_model=list[FileDiff])
@router.get("/api/antigravity/run/{run_id}/diff", response_model=list[FileDiff])
async def get_run_diff(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> list[FileDiff]:
    """Retorna o diff Git dos arquivos modificados pela execução."""
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")

    result = await db.execute(select(Project).where(Project.id == run.project_id))
    project = result.scalar_one_or_none()
    if not project:
        raise HTTPException(status_code=404, detail="Projeto não encontrado")

    files = json.loads(run.files_changed) if run.files_changed else []
    diffs: list[FileDiff] = []
    for f in files:
        diff_resp = get_diff(project.path, f)
        diffs.append(FileDiff(path=f, status="modified", diff=diff_resp.diff))
    return diffs


def _remove_empty_parents(abs_path: str, project_path: str):
    parent = os.path.dirname(abs_path)
    while parent and parent != project_path and len(parent) > len(project_path):
        if os.path.exists(parent) and os.path.isdir(parent):
            try:
                contents = os.listdir(parent)
                if not contents:
                    os.rmdir(parent)
                else:
                    break
            except Exception:
                break
        else:
            break
        parent = os.path.dirname(parent)


@router.post("/api/mimo/run/{run_id}/approve")
@router.post("/api/antigravity/run/{run_id}/approve")
async def approve_run(
    run_id: int,
    body: AntigravityApproveRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Aprova ou rejeita as mudanças de uma execução do Mimo.
    """
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")

    result = await db.execute(select(Project).where(Project.id == run.project_id))
    project = result.scalar_one_or_none()

    if body.approve:
        run.status = "approved"
        message = "Mudanças aprovadas"
        # Limpa o snapshot físico correspondente
        try:
            snapshot_path = os.path.join("snapshots", f"{run_id}.json")
            if os.path.exists(snapshot_path):
                os.remove(snapshot_path)
        except Exception:
            pass
    else:
        run.status = "rejected"
        snapshot_restored = False
        
        # 1. Tentar restaurar do snapshot físico primeiro (mais seguro e preserva uncommitted changes alheios)
        try:
            snapshot_path = os.path.join("snapshots", f"{run_id}.json")
            if os.path.exists(snapshot_path):
                with open(snapshot_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                project_path = data["project_path"]
                file_contents = data["file_contents"]
                for rel_path, content in file_contents.items():
                    abs_path = os.path.join(project_path, rel_path)
                    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
                    with open(abs_path, "w", encoding="utf-8") as f:
                        f.write(content)
                # Apaga arquivos novos
                if run.files_changed:
                    files = json.loads(run.files_changed)
                    for f in files:
                        if f not in file_contents:
                            abs_path = os.path.join(project_path, f)
                            if os.path.isfile(abs_path):
                                os.remove(abs_path)
                                _remove_empty_parents(abs_path, project_path)
                snapshot_restored = True
                try:
                    os.remove(snapshot_path)
                except Exception:
                    pass
        except Exception:
            pass

        # 2. Fallback para Git
        if not snapshot_restored and project:
            try:
                import git
                repo = git.Repo(project.path, search_parent_directories=True)
                repo_dir = repo.working_tree_dir
                files = json.loads(run.files_changed) if run.files_changed else []
                for rel_path in files:
                    abs_path = os.path.join(project.path, rel_path)
                    git_rel_path = os.relpath(abs_path, repo_dir)
                    if git_rel_path in repo.untracked_files:
                        try:
                            os.remove(abs_path)
                            _remove_empty_parents(abs_path, project.path)
                        except Exception:
                            pass
                    else:
                        try:
                            repo.git.checkout("--", abs_path)
                        except Exception:
                            pass
            except Exception:
                pass
        message = "Mudanças rejeitadas e revertidas"

    await db.commit()
    return {"message": message, "status": run.status}


class SnapshotSaveRequest(BaseModel):
    project_id: int
    run_id: int
    files: list[str] | None = None


@router.post("/api/mimo/snapshot/save")
async def save_snapshot(
    body: SnapshotSaveRequest,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Cria um backup físico no agente dos arquivos do projeto antes da execução.
    """
    project_path = await _project_path(body.project_id, db)
    file_contents = {}
    
    files_to_backup = body.files
    if not files_to_backup:
        files_to_backup = []
        for root, dirs, files in os.walk(project_path):
            if any(ignored in root.replace("\\", "/").split("/") for ignored in (".git", "node_modules", ".mimocode")):
                continue
            for file in files:
                abs_path = os.path.join(root, file)
                rel_path = os.relpath(abs_path, project_path).replace("\\", "/")
                files_to_backup.append(rel_path)
    
    for rel_path in files_to_backup:
        abs_path = os.path.join(project_path, rel_path)
        if os.path.isfile(abs_path):
            try:
                with open(abs_path, "r", encoding="utf-8", errors="ignore") as f:
                    file_contents[rel_path] = f.read()
            except Exception:
                pass

    os.makedirs("snapshots", exist_ok=True)
    snapshot_path = os.path.join("snapshots", f"{body.run_id}.json")
    with open(snapshot_path, "w", encoding="utf-8") as f:
        json.dump({
            "project_id": body.project_id,
            "project_path": project_path,
            "file_contents": file_contents
        }, f, indent=2)

    return {"message": f"Snapshot saved for run {body.run_id}", "files_backed_up": len(file_contents)}


@router.post("/api/mimo/snapshot/restore/{run_id}")
async def restore_snapshot(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Restaura o backup físico ou faz fallback para Git.
    """
    snapshot_path = os.path.join("snapshots", f"{run_id}.json")
    if not os.path.exists(snapshot_path):
        # Fallback Git se o snapshot não existir
        run = await db.get(AntigravityRun, run_id)
        if run:
            result = await db.execute(select(Project).where(Project.id == run.project_id))
            project = result.scalar_one_or_none()
            if project:
                try:
                    import git
                    repo = git.Repo(project.path, search_parent_directories=True)
                    repo_dir = repo.working_tree_dir
                    files = json.loads(run.files_changed) if run.files_changed else []
                    for rel_path in files:
                        abs_path = os.path.join(project.path, rel_path)
                        git_rel_path = os.relpath(abs_path, repo_dir)
                        if git_rel_path in repo.untracked_files:
                            try:
                                os.remove(abs_path)
                                _remove_empty_parents(abs_path, project.path)
                            except Exception:
                                pass
                        else:
                            try:
                                repo.git.checkout("--", abs_path)
                            except Exception:
                                pass
                    return {"message": "Restaurado via Git (sem snapshot físico)"}
                except Exception as e:
                    raise HTTPException(status_code=404, detail=f"Erro ao restaurar via Git: {e}")
        raise HTTPException(status_code=404, detail="Snapshot não encontrado")

    try:
        with open(snapshot_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        project_path = data["project_path"]
        file_contents = data["file_contents"]
        
        for rel_path, content in file_contents.items():
            abs_path = os.path.join(project_path, rel_path)
            os.makedirs(os.path.dirname(abs_path), exist_ok=True)
            with open(abs_path, "w", encoding="utf-8") as f:
                f.write(content)
                
        # Apaga novos arquivos criados
        run = await db.get(AntigravityRun, run_id)
        if run and run.files_changed:
            files = json.loads(run.files_changed)
            for f in files:
                if f not in file_contents:
                    abs_path = os.path.join(project_path, f)
                    if os.path.isfile(abs_path):
                        try:
                            os.remove(abs_path)
                            _remove_empty_parents(abs_path, project_path)
                        except Exception:
                            pass
        
        return {"message": f"Snapshot {run_id} restaurado com sucesso"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/mimo/snapshot/{run_id}")
async def delete_snapshot(
    run_id: int,
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Remove o snapshot físico correspondente.
    """
    snapshot_path = os.path.join("snapshots", f"{run_id}.json")
    if os.path.exists(snapshot_path):
        try:
            os.remove(snapshot_path)
            return {"message": "Snapshot deletado"}
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
    return {"message": "Snapshot não existia"}


@router.delete("/api/mimo/run/{run_id}")
@router.delete("/api/antigravity/run/{run_id}")
async def delete_run(
    run_id: int,
    db: AsyncSession = Depends(get_db),
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Remove uma execução do histórico do banco de dados.
    """
    run = await db.get(AntigravityRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Execução não encontrada")

    await db.delete(run)
    await db.commit()
    return {"message": f"Execução {run_id} excluída do histórico"}


class SnapshotRenameRequest(BaseModel):
    old_run_id: int
    new_run_id: int


@router.post("/api/mimo/snapshot/rename")
async def rename_snapshot(
    body: SnapshotRenameRequest,
    _: dict = Depends(get_current_user),
) -> dict:
    """
    Renomeia o snapshot físico correspondente.
    """
    os.makedirs("snapshots", exist_ok=True)
    old_path = os.path.join("snapshots", f"{body.old_run_id}.json")
    new_path = os.path.join("snapshots", f"{body.new_run_id}.json")
    if os.path.exists(old_path):
        try:
            os.rename(old_path, new_path)
            return {"message": f"Snapshot renamed from {body.old_run_id} to {body.new_run_id}"}
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
    return {"message": "Snapshot de origem não existia"}



@router.get("/api/mimo/models", response_model=list[MimoModelInfo])
@router.get("/api/antigravity/models", response_model=list[MimoModelInfo])
async def get_models(
    _: dict = Depends(get_current_user),
) -> list[MimoModelInfo]:
    """Retorna os modelos de IA relevantes (limitado aos principais provedores)."""
    global _models_cache, _models_cache_ts
    
    if _models_cache is not None and (time.monotonic() - _models_cache_ts) < _MODELS_CACHE_TTL:
        return _models_cache
    
    _FEATURED_PROVIDERS = {
        "xiaomi-token-plan-sgp", "anthropic", "google", "openai", "xai",
        "deepseek", "meta", "mistral", "qwen", "cohere", "perplexity",
        "openrouter", "ollama-cloud",
    }
    _MAX_PER_PROVIDER = 30
    _MAX_TOTAL = 300
    
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get("https://models.dev/api.json", timeout=15)
            if resp.status_code == 200:
                data = resp.json()
            else:
                data = {}
    except Exception:
        data = {}

    models_list = []
    provider_count: dict[str, int] = {}
    
    _POPULAR_KEYWORDS = ["anthropic", "google", "openai", "xai", "x-ai", "deepseek"]
    _MIMO_KEYWORDS = ["xiaomi", "mimo"]
    _LOCAL_KEYWORDS = ["ollama"]
    
    def _is_popular(pid: str) -> bool:
        return any(k in pid for k in _POPULAR_KEYWORDS)
    
    def _is_mimo(pid: str) -> bool:
        return any(k in pid for k in _MIMO_KEYWORDS)
    
    def _is_local(pid: str) -> bool:
        return any(k in pid for k in _LOCAL_KEYWORDS)
    
    for provider_id, provider_info in data.items():
        if provider_id not in _FEATURED_PROVIDERS:
            continue
        provider_name = provider_info.get("name", provider_id.capitalize())
        models = provider_info.get("models", {})
        provider_count[provider_id] = 0
        for model_id, model_info in models.items():
            if provider_count.get(provider_id, 0) >= _MAX_PER_PROVIDER:
                break
            if len(models_list) >= _MAX_TOTAL:
                break
            full_id = f"{provider_id}/{model_id}"
            
            logo = "🤖"
            color = "#10A37F"
            key_url = ""
            key_hint = "Chave da API"
            category = "api"
            
            p_lower = provider_id.lower()
            p_name_lower = provider_name.lower()
            combined = p_lower + " " + p_name_lower
            
            if _is_local(combined):
                category = "local"
                logo = "💻"
                color = "#4CAF50"
                key_url = "https://ollama.com"
                key_hint = "Rod localmente"
            elif _is_mimo(combined):
                category = "mimo"
                logo = "🔶"
                color = "#FF6900"
                key_url = "https://platform.xiaomimimo.com"
                # Somente mimo-auto é gratuito; todos os outros precisam de API key
                key_hint = "" if model_id.lower() == "mimo-auto" else "API Key Xiaomi MiMo"
                if "tts" in model_id.lower():
                    logo = "🔊"
                elif "omni" in model_id.lower():
                    logo = "🌐"
            elif _is_popular(combined):
                category = "popular"
                if "anthropic" in combined:
                    logo = "🧠"
                    color = "#D4A27F"
                    key_url = "https://console.anthropic.com/keys"
                    key_hint = "sk-ant-..."
                elif "google" in combined or "gemini" in combined:
                    logo = "🔮"
                    color = "#4285F4"
                    key_url = "https://aistudio.google.com/apikey"
                    key_hint = "AIzaSy..."
                elif "openai" in combined:
                    logo = "🤖"
                    color = "#10A37F"
                    key_url = "https://platform.openai.com/api-keys"
                    key_hint = "sk-proj-..."
                elif "deepseek" in combined:
                    logo = "🐋"
                    color = "#4F6EF7"
                    key_url = "https://platform.deepseek.com/api_keys"
                    key_hint = "sk-..."
                elif "xai" in combined or "grok" in combined:
                    logo = "⚡"
                    color = "#1DA1F2"
                    key_url = "https://console.x.ai"
                    key_hint = "xai-..."
            else:
                # Provider-specific branding for known providers
                if "openrouter" in combined:
                    logo = "🌐"
                    color = "#FF5722"
                    key_url = "https://openrouter.ai/keys"
                    key_hint = "sk-or-..."
                elif "mistral" in combined:
                    logo = "🌀"
                    color = "#FF7000"
                    key_url = "https://console.mistral.ai"
                    key_hint = "..."
                elif "meta" in combined or "llama" in combined:
                    logo = "🦙"
                    color = "#0668E1"
                    key_url = "https://llama.meta.com"
                    key_hint = "..."
                elif "qwen" in combined:
                    logo = "🔮"
                    color = "#6C5CE7"
                    key_url = "https://dashscope.aliyun.com"
                    key_hint = "..."
                elif "cohere" in combined:
                    logo = "🔷"
                    color = "#39D98A"
                    key_url = "https://dashboard.cohere.com"
                    key_hint = "..."
                elif "perplexity" in combined:
                    logo = "🌐"
                    color = "#20B2AA"
                    key_url = "https://perplexity.ai"
                    key_hint = "..."
                    
            models_list.append(MimoModelInfo(
                id=full_id,
                name=model_info.get("name", model_id),
                provider=provider_name,
                logoAsset=logo,
                color=color,
                keyUrl=key_url,
                keyHint=key_hint,
                category=category,
                toolCall=model_info.get("tool_call", True),
                reasoning=model_info.get("reasoning", False),
            ))
            provider_count[provider_id] = provider_count.get(provider_id, 0) + 1
            
    # Caso models.dev retorne vazio, retorna alguns fallbacks
    if not models_list:
        models_list = [
            MimoModelInfo(
                id="mimo/mimo-auto",
                name="MiMo Auto (Gratuito)",
                provider="Mimo",
                logoAsset="✨",
                color="#8A2BE2",
                keyUrl="https://mimo.ai",
                keyHint="Free",
                category="mimo",
            ),
            MimoModelInfo(
                id="xiaomi/mimo-v2.5-pro",
                name="MiMo V2.5 Pro",
                provider="Xiaomi",
                logoAsset="🔶",
                color="#FF6900",
                keyUrl="https://platform.xiaomimimo.com",
                keyHint="API Key necessária",
                category="mimo",
            ),
            MimoModelInfo(
                id="google/gemini-2.5-flash",
                name="Gemini 2.5 Flash",
                provider="Google",
                logoAsset="🔮",
                color="#4285F4",
                keyUrl="https://aistudio.google.com/apikey",
                keyHint="AIzaSy...",
                category="popular",
            ),
            MimoModelInfo(
                id="anthropic/claude-sonnet-4-5",
                name="Claude Sonnet 4.5",
                provider="Anthropic",
                logoAsset="🧠",
                color="#D4A27F",
                keyUrl="https://console.anthropic.com/keys",
                keyHint="sk-ant-...",
                category="popular",
            ),
            MimoModelInfo(
                id="openai/gpt-4o-mini",
                name="GPT-4o Mini",
                provider="OpenAI",
                logoAsset="⚡",
                color="#10A37F",
                keyUrl="https://platform.openai.com/api-keys",
                keyHint="sk-proj-...",
                category="popular",
            ),
            MimoModelInfo(
                id="deepseek/deepseek-chat",
                name="DeepSeek V3",
                provider="DeepSeek",
                logoAsset="🐋",
                color="#4F6EF7",
                keyUrl="https://platform.deepseek.com/api_keys",
                keyHint="sk-...",
                category="popular",
            ),
        ]
        
    _models_cache = models_list
    _models_cache_ts = time.monotonic()
    return models_list


@router.get("/api/mimo/functions", response_model=list[MimoFunctionInfo])
@router.get("/api/antigravity/functions", response_model=list[MimoFunctionInfo])
async def get_functions(
    _: dict = Depends(get_current_user),
) -> list[MimoFunctionInfo]:
    """Retorna a lista de funções (ferramentas) do MiMo Code."""
    return [
        MimoFunctionInfo(name="read", description="Lê o conteúdo completo ou parcial de um arquivo do projeto."),
        MimoFunctionInfo(name="write", description="Cria ou sobrescreve completamente um arquivo do projeto."),
        MimoFunctionInfo(name="edit", description="Modifica blocos de linhas de forma inteligente usando patches."),
        MimoFunctionInfo(name="glob", description="Localiza arquivos correspondentes a um padrão glob."),
        MimoFunctionInfo(name="grep", description="Busca por um padrão de texto no projeto usando ripgrep."),
        MimoFunctionInfo(name="bash", description="Executa um comando de shell no diretório do projeto."),
        MimoFunctionInfo(name="codesearch", description="Busca semântica avançada no codebase."),
        MimoFunctionInfo(name="websearch", description="Realiza busca na web para consultar documentação ou problemas."),
        MimoFunctionInfo(name="webfetch", description="Obtém o conteúdo textual de qualquer página web ou URL."),
        MimoFunctionInfo(name="actor", description="Delega uma sub-tarefa complexa para outro sub-agente especializado."),
        MimoFunctionInfo(name="skill", description="Carrega um conjunto de instruções específicas (skills) no contexto."),
        MimoFunctionInfo(name="memory", description="Consulta e gerencia a memória persistente do projeto (MEMORY.md)."),
        MimoFunctionInfo(name="task", description="Gerencia e acompanha o progresso de tarefas divididas em etapas."),
        MimoFunctionInfo(name="history", description="Consulta o histórico de comandos e interações do terminal."),
    ]
