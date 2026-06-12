"""
RDC Agent — Serviço Antigravity (Engine AI Autônoma Completa)

Ferramentas disponíveis para a IA, equivalentes ao Antigravity IDE:
  - list_directory      → Listar arquivos/pastas
  - read_file           → Ler arquivo
  - read_multiple_files → Ler vários arquivos de uma vez
  - write_file          → Criar/sobrescrever arquivo
  - create_directory    → Criar pasta
  - delete_file         → Deletar arquivo ou pasta vazia
  - rename_file         → Renomear/mover arquivo
  - search_code         → Buscar texto em arquivos (com contexto de linhas)
  - run_command         → Executar comando shell no projeto
  - get_git_status      → Ver status do git
  - git_diff            → Ver diff de um arquivo
  - git_commit          → Fazer commit
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import subprocess
import shutil
from pathlib import Path
from typing import AsyncGenerator

from litellm import acompletion

from config import get_settings

settings = get_settings()

# ── Definição das ferramentas ─────────────────────────────────────────────────

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "Lista todos os arquivos e subpastas de um diretório do projeto. Use '.' para a raiz.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo. Ex: '.' ou 'src/components'"},
                    "recursive": {"type": "boolean", "description": "Se true, lista recursivamente (padrão: false)"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Lê o conteúdo completo de um arquivo. Pode especificar intervalo de linhas.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo do arquivo"},
                    "start_line": {"type": "integer", "description": "Linha inicial (opcional, 1-indexed)"},
                    "end_line": {"type": "integer", "description": "Linha final (opcional, 1-indexed)"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_multiple_files",
            "description": "Lê o conteúdo de vários arquivos de uma vez (mais eficiente que múltiplas chamadas de read_file).",
            "parameters": {
                "type": "object",
                "properties": {
                    "paths": {"type": "array", "items": {"type": "string"}, "description": "Lista de caminhos relativos"}
                },
                "required": ["paths"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Cria ou sobrescreve completamente um arquivo. Cria diretórios intermediários se necessário.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo do arquivo"},
                    "content": {"type": "string", "description": "Conteúdo completo do arquivo"}
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "create_directory",
            "description": "Cria um diretório (e diretórios pai se necessário).",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo do diretório a criar"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_file",
            "description": "Deleta um arquivo ou diretório vazio do projeto.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo do arquivo ou pasta"},
                    "recursive": {"type": "boolean", "description": "Se true, deleta pasta recursivamente (padrão: false)"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "rename_file",
            "description": "Renomeia ou move um arquivo/pasta dentro do projeto.",
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {"type": "string", "description": "Caminho relativo de origem"},
                    "destination": {"type": "string", "description": "Caminho relativo de destino"}
                },
                "required": ["source", "destination"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_code",
            "description": "Busca por um padrão de texto em todos os arquivos do projeto. Retorna os arquivos que contêm o texto e as linhas de contexto.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Texto ou regex a buscar"},
                    "file_pattern": {"type": "string", "description": "Filtro de extensão, ex: '*.py' ou '*.dart' (opcional)"},
                    "context_lines": {"type": "integer", "description": "Número de linhas de contexto antes/depois (padrão: 2)"}
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Executa um comando shell no diretório do projeto. Use para rodar testes, instalar dependências, compilar, etc.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Comando a executar. Ex: 'npm test', 'pip install requests', 'flutter analyze'"},
                    "timeout": {"type": "integer", "description": "Timeout em segundos (padrão: 30)"}
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_git_status",
            "description": "Retorna o status atual do repositório Git (arquivos modificados, novos, deletados, branch atual).",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "git_diff",
            "description": "Retorna o diff de um arquivo ou de todos os arquivos modificados.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Caminho relativo do arquivo (opcional — omitir para ver diff geral)"}
                },
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "git_commit",
            "description": "Adiciona todos os arquivos modificados e faz um commit.",
            "parameters": {
                "type": "object",
                "properties": {
                    "message": {"type": "string", "description": "Mensagem do commit"}
                },
                "required": ["message"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_subagent",
            "description": "Delega uma sub-tarefa complexa para outra instância do agente (recursividade). Útil para quebrar grandes problemas em partes menores e contornar limites de contexto ou passos.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task": {"type": "string", "description": "Descrição detalhada e completa da tarefa que o sub-agente deve resolver"}
                },
                "required": ["task"]
            }
        }
    },
]

# ── Implementação das ferramentas ─────────────────────────────────────────────

def _resolve(project_path: str, rel_path: str) -> Path:
    """Resolve caminho relativo com proteção contra path traversal."""
    base = Path(project_path).resolve()
    p = (base / rel_path.lstrip("/").lstrip("\\")).resolve()
    if base not in p.parents and p != base:
        raise ValueError(f"Acesso negado: '{rel_path}' está fora do projeto")
    return p


def _fmt_dir(path: Path, base: Path, recursive: bool, _depth: int = 0) -> str:
    """Formata listagem de diretório em árvore."""
    lines = []
    indent = "  " * _depth
    try:
        items = sorted(path.iterdir(), key=lambda x: (x.is_file(), x.name))
    except PermissionError:
        return f"{indent}[sem permissão]"
    for item in items:
        if item.name in {".git", "__pycache__", "node_modules", ".dart_tool", "build"}:
            continue
        if item.is_dir():
            lines.append(f"{indent}📁 {item.name}/")
            if recursive and _depth < 4:
                lines.append(_fmt_dir(item, base, recursive, _depth + 1))
        else:
            size = item.stat().st_size
            size_str = f"{size}B" if size < 1024 else f"{size//1024}KB"
            lines.append(f"{indent}📄 {item.name} ({size_str})")
    return "\n".join(lines) if lines else f"{indent}(vazio)"


def execute_tool(name: str, args: dict, project_path: str) -> str:  # noqa: C901
    try:
        # ── list_directory ────────────────────────────────────────────────────
        if name == "list_directory":
            p = _resolve(project_path, args.get("path", "."))
            if not p.is_dir():
                return f"Erro: '{args['path']}' não é um diretório."
            recursive = args.get("recursive", False)
            tree = _fmt_dir(p, Path(project_path), recursive)
            rel = p.relative_to(project_path)
            return f"📁 {rel}/\n{tree}"

        # ── read_file ─────────────────────────────────────────────────────────
        elif name == "read_file":
            p = _resolve(project_path, args["path"])
            if not p.is_file():
                return f"Erro: arquivo '{args['path']}' não existe."
            try:
                lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
            except UnicodeDecodeError:
                return f"Erro: arquivo '{args['path']}' é binário."
            start = args.get("start_line", 1) - 1
            end   = args.get("end_line", len(lines))
            chunk = lines[max(0, start):end]
            numbered = "".join(f"{start+i+1:4d}: {l}" for i, l in enumerate(chunk))
            return f"```{p.suffix.lstrip('.')}\n{numbered}\n```"

        # ── read_multiple_files ───────────────────────────────────────────────
        elif name == "read_multiple_files":
            parts = []
            for rel in args.get("paths", []):
                p = _resolve(project_path, rel)
                if not p.is_file():
                    parts.append(f"=== {rel} ===\nArquivo não existe.\n")
                    continue
                try:
                    content = p.read_text(encoding="utf-8")
                    parts.append(f"=== {rel} ===\n```{p.suffix.lstrip('.')}\n{content}\n```\n")
                except UnicodeDecodeError:
                    parts.append(f"=== {rel} ===\n(arquivo binário)\n")
            return "\n".join(parts) if parts else "Nenhum arquivo lido."

        # ── write_file ────────────────────────────────────────────────────────
        elif name == "write_file":
            p = _resolve(project_path, args["path"])
            content = args.get("content", "")
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")
            lines = content.count("\n") + 1
            return f"✅ '{args['path']}' salvo ({lines} linhas)."

        # ── create_directory ──────────────────────────────────────────────────
        elif name == "create_directory":
            p = _resolve(project_path, args["path"])
            p.mkdir(parents=True, exist_ok=True)
            return f"✅ Diretório '{args['path']}' criado."

        # ── delete_file ───────────────────────────────────────────────────────
        elif name == "delete_file":
            p = _resolve(project_path, args["path"])
            if not p.exists():
                return f"Erro: '{args['path']}' não existe."
            if p.is_file():
                p.unlink()
                return f"✅ Arquivo '{args['path']}' deletado."
            elif p.is_dir():
                if args.get("recursive", False):
                    shutil.rmtree(p)
                    return f"✅ Pasta '{args['path']}' deletada recursivamente."
                else:
                    p.rmdir()
                    return f"✅ Pasta vazia '{args['path']}' deletada."

        # ── rename_file ───────────────────────────────────────────────────────
        elif name == "rename_file":
            src = _resolve(project_path, args["source"])
            dst = _resolve(project_path, args["destination"])
            if not src.exists():
                return f"Erro: '{args['source']}' não existe."
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dst))
            return f"✅ '{args['source']}' → '{args['destination']}'."

        # ── search_code ───────────────────────────────────────────────────────
        elif name == "search_code":
            query       = args.get("query", "")
            file_pat    = args.get("file_pattern", "")
            ctx_lines   = int(args.get("context_lines", 2))
            results     = []
            skip_dirs   = {".git", "__pycache__", "node_modules", ".dart_tool", "build"}

            for root, dirs, files in os.walk(project_path):
                dirs[:] = [d for d in dirs if d not in skip_dirs]
                for fname in files:
                    if file_pat and not fname.endswith(file_pat.lstrip("*")):
                        continue
                    fp = Path(root) / fname
                    try:
                        content_lines = fp.read_text(encoding="utf-8").splitlines()
                    except Exception:
                        continue

                    for i, line in enumerate(content_lines):
                        if query.lower() in line.lower():
                            rel = fp.relative_to(project_path)
                            start = max(0, i - ctx_lines)
                            end   = min(len(content_lines), i + ctx_lines + 1)
                            snippet = "\n".join(
                                f"{'→' if j == i else ' '} {start+j+1:4d}: {content_lines[start+j]}"
                                for j in range(end - start)
                            )
                            results.append(f"📄 {rel}:{i+1}\n{snippet}")
                            break  # uma ocorrência por arquivo é suficiente

            if not results:
                return f"Nenhum resultado para '{query}'."
            return f"Encontrado em {len(results)} arquivo(s):\n\n" + "\n\n".join(results)

        # ── run_command ───────────────────────────────────────────────────────
        elif name == "run_command":
            command = args.get("command", "")
            timeout = int(args.get("timeout", 30))
            try:
                proc = subprocess.run(
                    command, shell=True, cwd=project_path,
                    capture_output=True, text=True, timeout=timeout,
                    encoding="utf-8", errors="replace"
                )
                output = proc.stdout + proc.stderr
                status = "✅ sucesso" if proc.returncode == 0 else f"❌ código {proc.returncode}"
                out_truncated = output[:3000] + ("...[truncado]" if len(output) > 3000 else "")
                return f"$ {command}\n[{status}]\n{out_truncated}"
            except subprocess.TimeoutExpired:
                return f"❌ Timeout após {timeout}s."
            except Exception as e:
                return f"❌ Erro ao executar comando: {e}"

        # ── get_git_status ────────────────────────────────────────────────────
        elif name == "get_git_status":
            try:
                proc = subprocess.run(
                    ["git", "status", "--short", "--branch"],
                    cwd=project_path, capture_output=True, text=True, timeout=10
                )
                return proc.stdout or "Repositório limpo."
            except Exception as e:
                return f"Erro git status: {e}"

        # ── git_diff ──────────────────────────────────────────────────────────
        elif name == "git_diff":
            path = args.get("path", "")
            cmd = ["git", "diff", "--", path] if path else ["git", "diff"]
            try:
                proc = subprocess.run(
                    cmd, cwd=project_path, capture_output=True, text=True, timeout=10
                )
                diff = proc.stdout or "Sem diferenças."
                return diff[:4000] + ("...[truncado]" if len(diff) > 4000 else "")
            except Exception as e:
                return f"Erro git diff: {e}"

        # ── git_commit ────────────────────────────────────────────────────────
        elif name == "git_commit":
            message = args.get("message", "Automated commit by Antigravity")
            try:
                subprocess.run(["git", "add", "-A"], cwd=project_path, timeout=10, check=True)
                proc = subprocess.run(
                    ["git", "commit", "-m", message],
                    cwd=project_path, capture_output=True, text=True, timeout=10
                )
                return proc.stdout or proc.stderr or "Commit realizado."
            except Exception as e:
                return f"Erro git commit: {e}"

        return f"Ferramenta '{name}' não reconhecida."

    except ValueError as e:
        return str(e)
    except Exception as e:
        return f"❌ Erro em '{name}': {e}"


# ── Motor principal do agente ─────────────────────────────────────────────────

async def run_prompt(
    project_path: str,
    prompt: str,
    depth: int = 0,
) -> AsyncGenerator[str, None]:
    """
    Loop agêntico principal.
    A IA recebe o prompt, usa ferramentas em loop até concluir a tarefa.
    """
    # Pega configurações em tempo real (podem ter sido alteradas via /api/settings/ai)
    current = get_settings()
    model    = os.environ.get("AI_MODEL", current.ai_model)
    api_key  = os.environ.get("AI_API_KEY", current.ai_api_key)

    if not api_key:
        yield "❌ ERRO: Chave da IA (AI_API_KEY) não configurada!\n"
        yield "💡 Configure em: Antigravity → ⚙️ → Selecionar Modelo\n"
        return

    # Injeta a chave para todos os provedores suportados pelo LiteLLM
    _provider_env = {
        "gemini":    "GEMINI_API_KEY",
        "openai":    "OPENAI_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "deepseek":  "DEEPSEEK_API_KEY",
        "mistral":   "MISTRAL_API_KEY",
        "cohere":    "COHERE_API_KEY",
    }
    for prefix, env_var in _provider_env.items():
        if model.startswith(prefix):
            os.environ[env_var] = api_key
            break
    else:
        # Fallback: injeta em todos
        for env_var in _provider_env.values():
            os.environ[env_var] = api_key

    yield f"🚀 Antigravity Engine iniciado\n"
    yield f"🤖 Modelo: {model}\n"
    yield f"📁 Projeto: {os.path.basename(project_path)}\n\n"

    system = (
        f"<identity>\n"
        f"You are Antigravity, a powerful agentic AI coding assistant designed by the Google Deepmind team working on Advanced Agentic Coding.\n"
        f"You are pair programming with a USER to solve their coding task. The task may require creating a new codebase, modifying or debugging an existing codebase, or simply answering a question.\n"
        f"</identity>\n\n"
        f"Projeto atual: {project_path}\n\n"
        f"CRITICAL INSTRUCTIONS / REGRAS CRÍTICAS:\n"
        f"1. VOCÊ DEVE USAR AS FERRAMENTAS (como `write_file`) PARA CRIAR OU MODIFICAR ARQUIVOS. NUNCA envie o código completo no chat!\n"
        f"2. NUNCA envie blocos de código gigantes na sua resposta de texto. A resposta de texto serve apenas para conversar com o usuário.\n"
        f"3. Entenda o projeto usando `list_directory` e `read_file` antes de modificar.\n"
        f"4. Ao usar `write_file`, NUNCA resuma o código; envie o arquivo COMPLETO.\n"
        f"5. Após editar, valide usando `run_command` (ex: testes, lint).\n"
        f"6. O usuário quer que você aja de forma autônoma para resolver a tarefa criando os arquivos necessários.\n\n"
        f"<web_application_development>\n"
        f"## Technology Stack\n"
        f"1. **Core**: Use HTML for structure and Javascript for logic.\n"
        f"2. **Styling (CSS)**: Use Vanilla CSS for maximum flexibility and control.\n"
        f"3. **Web App**: If the USER specifies that they want a more complex web app, use a framework like Next.js or Vite.\n\n"
        f"## Design Aesthetics\n"
        f"1. **Use Rich Aesthetics**: Use best practices in modern web design (e.g. vibrant colors, dark modes, glassmorphism, and dynamic animations).\n"
        f"2. **Prioritize Visual Excellence**: Avoid generic colors. Use modern typography. Use smooth gradients and micro-animations.\n"
        f"3. **Use a Dynamic Design**: Achieve this with hover effects and interactive elements.\n"
        f"</web_application_development>"
    )

    messages: list[dict] = [
        {"role": "system", "content": system},
        {"role": "user",   "content": prompt},
    ]

    max_steps = 15
    step = 0

    while step < max_steps:
        step += 1
        try:
            response = await acompletion(
                model=model,
                messages=messages,
                tools=TOOLS,
                stream=True,
            )

            tool_calls_dict: dict[int, dict] = {}
            content_buf = ""

            async for chunk in response:
                delta = chunk.choices[0].delta

                if delta.content:
                    content_buf += delta.content
                    yield delta.content

                if hasattr(delta, "tool_calls") and delta.tool_calls:
                    for tc in delta.tool_calls:
                        idx = tc.index
                        if idx not in tool_calls_dict:
                            tool_calls_dict[idx] = {
                                "id": tc.id or f"call_{idx}",
                                "type": "function",
                                "function": {
                                    "name": tc.function.name if tc.function else "",
                                    "arguments": "",
                                },
                            }
                        if tc.function and tc.function.arguments:
                            tool_calls_dict[idx]["function"]["arguments"] += tc.function.arguments

            if content_buf and not content_buf.endswith("\n"):
                yield "\n"

            if not tool_calls_dict:
                # A IA terminou sem pedir ferramentas → tarefa concluída
                break

            # ── Processa tool calls ───────────────────────────────────────────
            tcs = list(tool_calls_dict.values())
            messages.append({
                "role": "assistant",
                "content": None,
                "tool_calls": tcs,
            })

            for tc in tcs:
                func_name = tc["function"]["name"]
                try:
                    func_args = json.loads(tc["function"]["arguments"])
                except Exception:
                    func_args = {}

                # Formata log compacto da ferramenta
                args_display = ", ".join(
                    f"{k}={repr(str(v))[:30]}{'...' if len(str(v)) > 30 else ''}"
                    for k, v in func_args.items()
                    if k != "content"  # não exibe content do write_file
                )
                agent_label = "Agente" if depth == 0 else f"Agente Sub({depth})"
                yield f"\n🛠️ [{agent_label}] Executando: {func_name}({args_display})\n"

                if func_name == "run_subagent":
                    if depth >= 2:
                        result = "❌ Limite de recursividade atingido (profundidade máxima: 2)."
                    else:
                        sub_task = func_args.get("task", "")
                        yield f"\n🚀 Iniciando Sub-agente para: {sub_task[:50]}...\n"
                        result = "Saída do Sub-agente:\n"
                        async for sub_chunk in run_prompt(project_path, f"SUA TAREFA DELEGADA:\n{sub_task}\n\nResolva de forma autônoma e termine.", depth=depth + 1):
                            yield sub_chunk
                            result += sub_chunk
                        yield f"\n✅ Sub-agente concluído.\n"
                else:
                    result = execute_tool(func_name, func_args, project_path)

                # Log resumido do resultado
                result_preview = result[:200] + ("...[ver saída completa]" if len(result) > 200 else "")
                yield f"   ↳ {result_preview}\n"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "name": func_name,
                    "content": result,
                })

        except Exception as e:
            yield f"\n❌ Erro na Engine AI (passo {step}): {e}\n"
            break

    if step >= max_steps:
        yield f"\n⚠️ Limite de {max_steps} passos atingido.\n"


# ── Detectar arquivos modificados ─────────────────────────────────────────────

def detect_changed_files(project_path: str, output_log: str) -> list[str]:
    """Extrai arquivos modificados pelo agente com base no log de execução."""
    changed: list[str] = []
    for line in output_log.splitlines():
        if "Executando: write_file" in line and "path=" in line:
            try:
                # Extrai path='...' ou path="..."
                for quote in ("'", '"'):
                    marker = f"path={quote}"
                    if marker in line:
                        after = line.split(marker, 1)[1]
                        path  = after.split(quote)[0]
                        if path and path not in changed:
                            changed.append(path)
                        break
            except Exception:
                pass
    return changed
