# Remote Dev Control (RDC) — Plano de Implementação

## Visão Geral

Plataforma self-hosted para desenvolvimento remoto via dispositivos móveis. O sistema é composto por dois componentes principais: um **Agente Desktop** (Python/FastAPI) que roda no computador principal, e um **Aplicativo Mobile** (Flutter) que serve como interface de controle.

---

## User Review Required

> [!IMPORTANT]
> Este é um projeto de grande porte. A implementação completa exige múltiplas fases. Este plano cobre a **Fase 1 (MVP)** com todos os módulos core. Fases subsequentes adicionarão Playwright, screenshots automáticos e integrações avançadas.

> [!WARNING]
> O app Flutter requer ambiente de desenvolvimento Flutter instalado (SDK, Android Studio ou Xcode). Confirme se o ambiente Flutter já está configurado na sua máquina.

> [!IMPORTANT]
> O Agente Desktop será exposto na rede local via HTTPS. Para acesso externo (fora da rede), será necessário um túnel (ex: ngrok, Cloudflare Tunnel) ou configuração de port forwarding. O RDC não gerencia isso automaticamente na v1.

---

## Open Questions

> [!IMPORTANT]
> **Q1 — Plataforma principal do Agente Desktop**: O agente vai rodar primariamente em **Windows**, **Linux**, ou ambos? Isso afeta como os terminais (CMD/PowerShell vs Bash) são detectados.

> [!IMPORTANT]
> **Q2 — Flutter vs Web App Mobile**: Deseja um app Flutter nativo (requer build e instalação no dispositivo), ou prefere começar com uma **Progressive Web App (PWA)** responsiva que roda direto no browser do celular sem instalação? A PWA seria mais rápida de desenvolver e distribuir.

> [!IMPORTANT]
> **Q3 — Autenticação inicial**: Para o MVP, a autenticação pode ser simplificada com uma **API Key** (token fixo configurado no agente) em vez de um sistema completo JWT com refresh tokens. Deseja o JWT completo desde o início?

> [!NOTE]
> **Q4 — Antigravity CLI**: O módulo de integração com Antigravity deve executar o CLI como subprocess e capturar output em tempo real. Existe algum comando específico do Antigravity CLI que devo conhecer? (ex: `antigravity run`, `antigravity --prompt "..."`)

> [!NOTE]
> **Q5 — Playwright**: Deve ser incluído no MVP ou em fase posterior?

---

## Arquitetura

```
[Celular]
    |  HTTPS / WSS
    v
[Agente RDC Desktop]  ←→  [Projetos no HD]
    |                       |
    FastAPI                 Git, Terminal, FS
    WebSocket               Antigravity CLI
    SQLite                  Dev Servers
    Proxy HTTP
```

### Comunicação
- **REST API** para operações de projeto, arquivos, git, testes
- **WebSocket** para terminal em tempo real, logs, status de processos
- **HTTP Proxy** para preview web (forward para portas locais)
- **TLS/SSL** auto-assinado gerado na primeira execução

---

## Estrutura de Arquivos

```
rdc/
├── agent/                          # Agente Desktop (Python)
│   ├── main.py                     # Entry point FastAPI
│   ├── config.py                   # Configurações e settings
│   ├── database.py                 # SQLite setup (SQLAlchemy)
│   ├── auth/
│   │   ├── jwt.py                  # JWT + Refresh Token
│   │   └── middleware.py           # Auth middleware
│   ├── api/
│   │   ├── router.py               # Agregador de rotas
│   │   ├── system.py               # /api/system (CPU, RAM, disco, OS)
│   │   ├── projects.py             # /api/projects (CRUD)
│   │   ├── files.py                # /api/files (navegação, CRUD, upload/download)
│   │   ├── git.py                  # /api/git (branch, commit, push, pull...)
│   │   ├── tests.py                # /api/tests (pytest, jest, etc)
│   │   ├── antigravity.py          # /api/antigravity (prompt, histórico)
│   │   ├── preview.py              # /api/preview (detecção de portas)
│   │   └── screenshots.py          # /api/screenshots
│   ├── websocket/
│   │   ├── terminal.py             # WS terminal (bash/cmd/powershell)
│   │   ├── logs.py                 # WS logs em tempo real
│   │   └── preview_ws.py           # WS para hot reload detection
│   ├── services/
│   │   ├── system_info.py          # psutil: CPU, RAM, disco, temperatura
│   │   ├── file_manager.py         # Operações de arquivo (scan incremental)
│   │   ├── git_service.py          # GitPython wrapper
│   │   ├── terminal_manager.py     # Gestão de sessões de terminal (pty)
│   │   ├── process_manager.py      # Subprocessos, captura de logs
│   │   ├── port_scanner.py         # Detectar portas abertas (dev servers)
│   │   ├── proxy_service.py        # Proxy reverso HTTP para preview
│   │   ├── antigravity_service.py  # Execução e captura do CLI
│   │   └── playwright_service.py   # Screenshots via Playwright
│   ├── models/
│   │   ├── project.py              # SQLAlchemy model: Project
│   │   ├── session.py              # SQLAlchemy model: Session
│   │   ├── antigravity.py          # SQLAlchemy model: AGHistory
│   │   ├── test_run.py             # SQLAlchemy model: TestRun
│   │   └── screenshot.py          # SQLAlchemy model: Screenshot
│   ├── schemas/                    # Pydantic schemas (request/response)
│   └── requirements.txt
│
└── mobile/                         # App Flutter
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart
    │   ├── core/
    │   │   ├── api/                # HTTP client + WS client
    │   │   ├── auth/               # JWT storage e refresh
    │   │   └── theme/              # Design system, cores, tipografia
    │   ├── features/
    │   │   ├── dashboard/          # Tela inicial: status da máquina
    │   │   ├── projects/           # Lista e gerenciamento de projetos
    │   │   ├── workspace/          # Container do workspace por projeto
    │   │   ├── files/              # Explorador de arquivos
    │   │   ├── editor/             # Editor de código + syntax highlight
    │   │   ├── terminal/           # Terminal interativo via WS
    │   │   ├── logs/               # Visualizador de logs em tempo real
    │   │   ├── git/                # Interface Git
    │   │   ├── tests/              # Execução e resultado de testes
    │   │   ├── antigravity/        # Módulo Antigravity CLI
    │   │   ├── preview/            # Preview web (WebView)
    │   │   └── settings/           # Configuração de conexão
    │   └── shared/
    │       ├── widgets/            # Componentes reutilizáveis
    │       └── providers/          # State management (Riverpod)
    └── pubspec.yaml
```

---

## Fases de Desenvolvimento

### Fase 1 — Agente Desktop Core (Semana 1-2)
- [ ] Setup do projeto Python com FastAPI
- [ ] Autenticação JWT completa
- [ ] API de Sistema (CPU, RAM, disco, OS, uptime)
- [ ] API de Projetos (CRUD + SQLite)
- [ ] API de Arquivos (navegação incremental, CRUD, upload/download)
- [ ] WebSocket Terminal (bash/cmd/powershell com sessões persistentes)
- [ ] WebSocket Logs (tail de processos em background)
- [ ] API Git (branch, commits, diff, commit, push, pull, checkout)
- [ ] API de Testes (pytest, jest, npm test)
- [ ] Proxy de Preview (detectar portas, redirecionar)
- [ ] Auto-geração de certificado TLS

### Fase 2 — App Flutter Core (Semana 2-3)
- [ ] Setup Flutter + Riverpod
- [ ] Tela de Settings (configurar URL do agente + login)
- [ ] Dashboard (status da máquina)
- [ ] Lista de Projetos
- [ ] Workspace container (tabs: Arquivos, Editor, Terminal, Git, Logs, Testes, Preview, Antigravity)
- [ ] Explorador de Arquivos
- [ ] Editor de Código (syntax highlight via `flutter_highlight`)
- [ ] Terminal interativo (WS)
- [ ] Logs em tempo real (WS)
- [ ] Interface Git
- [ ] Execução de Testes

### Fase 3 — Antigravity + Preview (Semana 3-4)
- [ ] Módulo Antigravity no agente (subprocess + captura output WS)
- [ ] Módulo Antigravity no app (prompt, histórico, diff de arquivos, aprovação)
- [ ] Preview Web no app (WebView com URL do proxy)
- [ ] Hot reload detection
- [ ] Visualização multi-dispositivo

### Fase 4 — Playwright + Screenshots (Semana 4+)
- [ ] Playwright service no agente
- [ ] Screenshots manuais e automáticos
- [ ] Histórico de screenshots
- [ ] Captura automática pós-Antigravity

---

## Proposed Changes

### Backend — Agente Desktop

#### [NEW] agent/main.py
Entry point FastAPI com CORS, rotas, middleware de auth, WebSocket handlers e inicialização do banco.

#### [NEW] agent/config.py
Configuração via `.env` + Pydantic Settings: porta, segredo JWT, paths de DB, certificado TLS.

#### [NEW] agent/database.py
SQLAlchemy async com SQLite. Setup das tabelas e session factory.

#### [NEW] agent/auth/jwt.py
Geração e validação de JWT + Refresh Token. Endpoints `/auth/login`, `/auth/refresh`, `/auth/logout`.

#### [NEW] agent/api/system.py
`GET /api/system` — retorna nome da máquina, OS, CPU%, RAM, disco, temperatura (psutil), uptime.

#### [NEW] agent/api/projects.py
`GET /api/projects`, `POST /api/projects`, `PUT /api/projects/{id}`, `DELETE /api/projects/{id}`, `POST /api/projects/{id}/favorite`.

#### [NEW] agent/api/files.py
`GET /api/files/{project_id}/tree` (incremental), `GET /api/files/{project_id}/read`, `POST /api/files`, `PUT /api/files`, `DELETE /api/files`, `POST /api/files/upload`, `GET /api/files/download`.

#### [NEW] agent/api/git.py
`GET /api/git/{project_id}/status`, `GET /api/git/{project_id}/log`, `GET /api/git/{project_id}/diff`, `POST /api/git/{project_id}/commit`, `POST /api/git/{project_id}/push`, `POST /api/git/{project_id}/pull`, `POST /api/git/{project_id}/checkout`, `POST /api/git/{project_id}/branch`.

#### [NEW] agent/api/tests.py
`POST /api/tests/{project_id}/run` — detecta runner disponível e executa. Retorna resultado via WS.

#### [NEW] agent/api/preview.py
`GET /api/preview/{project_id}/ports` — escaneia portas abertas. `GET /api/preview/proxy/{port}/{path}` — proxy reverso.

#### [NEW] agent/websocket/terminal.py
WS `/ws/terminal/{session_id}` — pty session com bash/cmd/powershell. Suporte a histórico e sessões persistentes.

#### [NEW] agent/websocket/logs.py
WS `/ws/logs/{process_id}` — transmite stdout/stderr de processos em execução.

#### [NEW] agent/requirements.txt
```
fastapi, uvicorn[standard], python-jose[cryptography], passlib[bcrypt],
python-multipart, sqlalchemy, aiosqlite, psutil, gitpython, pywinpty (Windows),
httpx, watchdog, playwright
```

---

### Mobile — App Flutter

#### [NEW] mobile/pubspec.yaml
Dependências: `flutter_riverpod`, `dio`, `web_socket_channel`, `flutter_highlight`, `webview_flutter`, `file_picker`, `shared_preferences`, `go_router`, `intl`, `percent_indicator`, `flutter_svg`.

#### [NEW] mobile/lib/core/api/api_client.dart
Cliente HTTP (Dio) com interceptor de JWT. Gerencia refresh automático de token.

#### [NEW] mobile/lib/core/api/ws_client.dart
Cliente WebSocket reutilizável com reconexão automática.

#### [NEW] mobile/lib/features/dashboard/
Exibe nome da máquina, OS, CPU, RAM, Disco, Temperatura, Uptime, lista de projetos recentes. Atualização periódica via polling ou WS.

#### [NEW] mobile/lib/features/workspace/
Container principal do projeto com bottom navigation ou tab bar: Arquivos | Editor | Terminal | Git | Logs | Testes | Antigravity | Preview.

#### [NEW] mobile/lib/features/editor/
Editor com `flutter_highlight` para syntax highlight. Suporte a múltiplas abas, busca/substituição, desfazer/refazer.

#### [NEW] mobile/lib/features/terminal/
Terminal interativo com xterm-like UI. Conecta via WebSocket ao agente. Histórico, scroll, copiar output.

#### [NEW] mobile/lib/features/antigravity/
Tela de prompt, histórico de execuções, visualização de diff, aprovação/rejeição de mudanças.

#### [NEW] mobile/lib/features/preview/
WebView apontando para `https://agente/proxy/{porta}`. Controles de viewport para simular diferentes dispositivos.

---

## Decisões de Design

| Decisão | Escolha | Razão |
|---|---|---|
| State management Flutter | Riverpod | Mais robusto que Provider, sem boilerplate do BLoC |
| ORM Python | SQLAlchemy (async) | Suporte nativo a async/await com FastAPI |
| Terminal backend | pywinpty (Win) / pty (Unix) | Sessões PTY reais com suporte a cores ANSI |
| Syntax highlight Flutter | flutter_highlight | Suporte a todas as linguagens pedidas |
| Proxy preview | httpx + ASGI middleware | Integrado ao FastAPI sem servidor extra |
| Certificado TLS | Auto-assinado (trustme) | Zero configuração manual |
| Scanning de arquivos | Carregamento incremental (por dir) | Suporta projetos grandes sem travar |

---

## Verification Plan

### Backend
```bash
# Iniciar o agente
cd rdc/agent && uvicorn main:app --host 0.0.0.0 --port 8000 --ssl-keyfile key.pem --ssl-certfile cert.pem

# Verificar docs automáticos
# Abrir https://localhost:8000/docs

# Testar autenticação
curl -k -X POST https://localhost:8000/auth/login -d '{"password":"admin"}'

# Testar sistema
curl -k -H "Authorization: Bearer TOKEN" https://localhost:8000/api/system
```

### Mobile
```bash
cd rdc/mobile
flutter run  # Android/iOS conectado via USB
```

### Manual
- Conectar o app ao agente na rede local
- Abrir um projeto real, navegar arquivos, editar um arquivo, fazer commit, executar teste
- Verificar preview web de um projeto Vite/Flask em execução
