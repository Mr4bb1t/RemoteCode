# Remote Dev Control (RDC)

**Plataforma self-hosted para desenvolvimento remoto via dispositivos móveis.**

> Controle projetos no seu computador diretamente pelo celular, sem AnyDesk ou TeamViewer.

---

## Estrutura

```
rdc/
├── agent/      # Agente Desktop (Python + FastAPI)
└── mobile/     # App Mobile (Flutter)
```

---

## 🚀 Iniciar o Agente Desktop

### 1. Instalar dependências

```powershell
cd rdc/agent
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
```

### 2. Configurar

```powershell
Copy-Item .env.example .env
# Edite .env e altere AGENT_PASSWORD
notepad .env
```

### 3. Iniciar

```powershell
.\.venv\Scripts\python main.py
```

O agente exibirá o IP e porta para conectar pelo celular.

---

## 📱 App Mobile (Flutter)

### Pré-requisitos
- Flutter SDK instalado (`C:\Users\hp909\flutter\bin\flutter.bat`)

### Instalar dependências

```powershell
cd rdc/mobile
C:\Users\hp909\flutter\bin\flutter.bat pub get
```

### Rodar no Android

```powershell
C:\Users\hp909\flutter\bin\flutter.bat run
```

---

## API Endpoints

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| POST | `/auth/login` | Login com senha |
| POST | `/auth/refresh` | Renovar token |
| GET | `/api/system` | Info do sistema |
| GET | `/api/projects` | Lista projetos |
| POST | `/api/projects` | Adicionar projeto |
| GET | `/api/files/{id}/tree` | Navegar arquivos |
| GET | `/api/files/{id}/read` | Ler arquivo |
| PUT | `/api/files/{id}/write` | Salvar arquivo |
| GET | `/api/git/{id}/status` | Status Git |
| POST | `/api/git/{id}/commit` | Commit |
| POST | `/api/git/{id}/push` | Push |
| POST | `/api/tests/{id}/run` | Executar testes |
| GET | `/api/preview/ports` | Portas abertas |
| POST | `/api/antigravity/run` | Executar prompt (SSE) |
| WS | `/ws/terminal/{id}` | Terminal PTY |
| WS | `/ws/logs/{id}` | Logs em tempo real |
| WS | `/ws/system` | Métricas do sistema |

---

## Segurança

- HTTPS com certificado auto-assinado (gerado automaticamente)
- JWT + Refresh Token rotativo
- Validação de path traversal em todas as operações de arquivo
- Rate limiting via middleware FastAPI

---

## Tecnologias

**Backend:** Python 3.11+, FastAPI, SQLAlchemy (async), SQLite, GitPython, pywinpty, psutil, trustme

**Frontend:** Flutter 3.16+, Riverpod, GoRouter, Dio, WebSocket, WebView, flutter_highlight
