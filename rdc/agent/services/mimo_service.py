"""
RDC Agent — Serviço Mimo (Integração com MiMo Code via CLI oficial)
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
from pathlib import Path
from typing import AsyncGenerator

from config import get_settings

settings = get_settings()

# Diretório home do MiMo (para configs/memória)
MIMO_HOME = Path(__file__).resolve().parent.parent.parent.parent / ".mimocode"


def get_mimo_path() -> str:
    """Retorna o caminho do executável mimo instalado globalmente via npm."""
    # Tenta encontrar o mimo no PATH
    found = shutil.which("mimo")
    if found:
        return found
    # Fallback: npm global bin no Windows
    npm_prefix = os.popen("npm prefix -g 2>nul").read().strip()
    if npm_prefix:
        candidate = Path(npm_prefix) / "mimo.cmd"
        if candidate.exists():
            return str(candidate)
        candidate = Path(npm_prefix) / "mimo"
        if candidate.exists():
            return str(candidate)
    return "mimo"


async def run_prompt(
    project_path: str,
    prompt: str,
) -> AsyncGenerator[str, None]:
    """
    Executa o agente Mimo via CLI oficial (`mimo run`) e faz streaming dos eventos.
    O CLI é instalado via: npm install -g @mimo-ai/cli
    """
    current_settings = get_settings()
    model = os.environ.get("AI_MODEL", current_settings.ai_model)
    api_key = os.environ.get("AI_API_KEY", current_settings.ai_api_key)

    # Início limpo — sem linhas de sistema
    pass

    # Variáveis de ambiente para provedores
    _provider_env = {
        "xiaomi":    "XIAOMI_API_KEY",
        "gemini":    "GEMINI_API_KEY",
        "google":    "GEMINI_API_KEY",
        "openai":    "OPENAI_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "deepseek":  "DEEPSEEK_API_KEY",
        "mistral":   "MISTRAL_API_KEY",
        "cohere":    "COHERE_API_KEY",
        "xai":       "XAI_API_KEY",
    }

    env = os.environ.copy()
    env["MIMOCODE_HOME"] = str(MIMO_HOME)

    for prefix, env_var in _provider_env.items():
        if model.lower().startswith(prefix):
            if api_key:
                env[env_var] = api_key
            break
    else:
        if api_key:
            for env_var in _provider_env.values():
                env[env_var] = api_key

    mimo_path = get_mimo_path()

    # ── Logs de diagnóstico detalhados ────────────────────────────────────────
    yield "\n──────────────────────────────────────────────────\n"
    yield f"Bin: {mimo_path}\n"
    # Header limpo sem emojis
    yield f"Modelo: {model}\n"
    yield f"Projeto: {os.path.basename(project_path)}\n\n"

    stderr_lines: list[str] = []

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
            cwd=str(project_path),
        )

        # Fila para stderr em tempo real
        _stderr_queue: asyncio.Queue[str | None] = asyncio.Queue()

        async def _read_stderr():
            while True:
                chunk = await process.stderr.readline()
                if not chunk:
                    await _stderr_queue.put(None)  # sentinel
                    break
                line = chunk.decode("utf-8", errors="replace").strip()
                if line:
                    stderr_lines.append(line)
                    await _stderr_queue.put(line)

        stderr_task = asyncio.create_task(_read_stderr())

        yield "Iniciando execucao...\n\n"

        async def _drain_stderr():
            """Emite todas as linhas de stderr pendentes na fila sem bloquear."""
            items = []
            while not _stderr_queue.empty():
                item = _stderr_queue.get_nowait()
                if item is not None:
                    items.append(item)
            return items

        # stdout é texto plano (sem --format json)
        while True:
            line_bytes = await process.stdout.readline()
            if not line_bytes:
                break
            line = line_bytes.decode("utf-8", errors="replace").rstrip()
            if not line:
                continue

            # Tenta parsear como JSON (caso o CLI emita eventos estruturados)
            try:
                event = json.loads(line)
                ev_type = event.get("type")

                if ev_type == "text":
                    part = event.get("part", {})
                    text = part.get("text", "")
                    if text:
                        clean = _sanitize_ai_text(text)
                        if clean:
                            yield clean + "\n"
                            print(clean, end="", flush=True)

                elif ev_type == "reasoning":
                    part = event.get("part", {})
                    reasoning = part.get("text", "")
                    if reasoning:
                        clean = _sanitize_ai_text(reasoning)
                        if clean:
                            yield f"  {clean}\n"

                elif ev_type == "tool_use":
                    part = event.get("part", {})
                    tool_name = part.get("tool", "tool")
                    state = part.get("state", {})
                    status = state.get("status")
                    inputs = state.get("input", {})
                    
                    msg = _format_tool_output(tool_name, inputs if isinstance(inputs, dict) else {}, "")
                    yield f"\n{msg}\n"
                    print(msg, end="", flush=True)
                    
                    if status == "completed":
                        output = state.get("output", "")
                        if output and len(output.strip()) > 0:
                            preview = output[:150].strip()
                            if len(output) > 150:
                                preview += "..."
                            yield f"   {preview}\n"
                    elif status == "error":
                        error = state.get("error", "Erro desconhecido")
                        yield f"   [ERRO] {error}\n"

                elif ev_type == "error":
                    err_val = event.get("error", "Erro interno")
                    if isinstance(err_val, dict):
                        error_msg = err_val.get("message", "Erro interno")
                    else:
                        error_msg = str(err_val)
                    yield f"\n[ERRO] {error_msg}\n"

                else:
                    # Evento desconhecido — ignora
                    pass

            except json.JSONDecodeError:
                # Saída plain-text — sanitiza e envia
                clean = _sanitize_line(line)
                if clean:
                    yield clean + "\n"
                    print(clean, flush=True)

            # Intercala stderr pendente em tempo real
            for err_line in await _drain_stderr():
                yield f"🟡 [stderr] {err_line}\n"

        await stderr_task
        # Drena qualquer stderr restante após stdout fechar
        while not _stderr_queue.empty():
            item = _stderr_queue.get_nowait()
            if item is not None:
                yield f"🟡 [stderr] {item}\n"
        await process.wait()

        if process.returncode != 0:
            if stderr_lines:
                yield f"\n[ERRO] Codigo {process.returncode}:\n"
                for err_line in stderr_lines[-5:]:
                    yield f"  {err_line}\n"
            else:
                yield f"\n[AVISO] Processo finalizou com codigo {process.returncode}\n"

    except FileNotFoundError:
        yield "\n[ERRO] Mimo CLI nao encontrado. Instale com: npm install -g @mimo-ai/cli\n"
    except Exception as e:
        yield f"\n[ERRO] {str(e)}\n"

def _sanitize_line(line: str) -> str:
    """Remove ruído do sistema e formata saída para exibição limpa."""
    line = line.strip()
    if not line:
        return ""
    
    # Padrões de ruído para filtrar
    _NOISE_PATTERNS = (
        "Warning:", "Note:", "info ", "█", "⠀", "Reading",
        "Resolving", "Downloading", "Got ", "Progress:",
        "Packages:", "npm warn", "npm notice", "added ",
        "Mimo Engine", "Modelo:", "Projeto:", "API Key",
        "api_key", "Chave", "configura", "Configura",
        " Selecionado", "selecionado", "GRÁTIS",
    )
    if any(p in line for p in _NOISE_PATTERNS):
        return ""
    if any(line.startswith(p) for p in ("Warning:", "Note:", "info ", "█", "⠀")):
        return ""
    
    # Remover timestamps e códigos ANSI
    import re
    line = re.sub(r'\x1b\[[0-9;]*m', '', line)  # ANSI codes
    line = re.sub(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}.*?─?\s*', '', line)  # timestamps
    
    return line


_TOOL_LABELS = {
    "read": "[READ]",
    "write": "[WRITE]",
    "edit": "[EDIT]",
    "glob": "[SEARCH]",
    "grep": "[FIND]",
    "bash": "[RUN]",
    "codesearch": "[AI-SEARCH]",
    "websearch": "[WEB]",
    "webfetch": "[FETCH]",
    "actor": "[AGENT]",
    "skill": "[SKILL]",
    "memory": "[MEMORY]",
    "task": "[TASK]",
}

def _format_tool_output(tool_name: str, inputs: dict, output: str) -> str:
    """Formata saída de tool de forma limpa e legível."""
    label = _TOOL_LABELS.get(tool_name, f"🔧 {tool_name}")
    
    # Simplificar display baseado no tool
    if tool_name in ("read", "write", "edit"):
        path = inputs.get("filePath", inputs.get("path", ""))
        if path:
            # Mostrar só nome do arquivo, não o path completo
            name = path.replace("\\", "/").split("/")[-1]
            return f"{label} {name}"
    elif tool_name == "bash":
        cmd = inputs.get("command", "")
        if cmd:
            # Mostrar só o comando principal
            cmd_short = cmd.split("|")[0].split("&&")[0].strip()[:60]
            return f"{label} `{cmd_short}`"
    elif tool_name == "grep":
        pattern = inputs.get("pattern", "")
        return f"{label} \"{pattern}\""
    elif tool_name == "glob":
        pattern = inputs.get("pattern", "")
        return f"{label} {pattern}"
    
    # Fallback genérico
    args = ", ".join(f"{k}" for k in inputs.keys()) if inputs else ""
    return f"{label}({args})"


def _sanitize_ai_text(text: str) -> str:
    """Limpa texto de resposta da IA, removendo ruído e formatando."""
    lines = text.split("\n")
    clean = []
    
    _SYSTEM_NOISE = (
        "API Key", "api_key", "Chave", "configura", "Configura",
        "Mimo Engine", "Modelo:", "Projeto:", "Selecionado", "selecionado",
        "GRÁTIS", "gratuito", "Free", "free",
    )
    
    for line in lines:
        stripped = line.strip()
        
        if not stripped:
            clean.append("")
            continue
        
        # Pular linhas de ruído
        if any(p in stripped for p in _SYSTEM_NOISE):
            continue
        if any(stripped.startswith(p) for p in _NOISE_PREFIXES if 'import' not in p):
            continue
        
        # Remover paths absolutos do projeto
        import re
        stripped = re.sub(r'C:\\[^\s]+', '...', stripped)
        stripped = re.sub(r'/home/[^\s]+', '...', stripped)
        stripped = re.sub(r'/Users/[^\s]+', '...', stripped)
        
        # Remover timestamps de log
        stripped = re.sub(r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}', '', stripped)
        
        clean.append(stripped)
    
    # Remover múltiplas linhas vazias consecutivas
    result = []
    prev_empty = False
    for line in clean:
        if not line:
            if not prev_empty:
                result.append(line)
            prev_empty = True
        else:
            result.append(line)
            prev_empty = False
    
    return "\n".join(result).strip()


_NOISE_PREFIXES = (
    "Warning:", "Note:", "info ", "█", "⠀", "Reading",
    "Resolving", "Downloading", "Got ", "Progress:",
    "Packages:", "npm warn", "npm notice", "added ",
)


def detect_changed_files(project_path: str, output_log: str) -> list[str]:
    """Extrai arquivos modificados pelo agente com base no log de execução."""
    changed = []
    for line in output_log.splitlines():
        if "Write " in line:
            parts = line.split("Write ")
            if len(parts) > 1:
                p = parts[1].strip().strip("'\"")
                if p and p not in changed:
                    changed.append(p)
        elif "Edit " in line:
            parts = line.split("Edit ")
            if len(parts) > 1:
                p = parts[1].strip().strip("'\"")
                if p and p not in changed:
                    changed.append(p)
    return changed
