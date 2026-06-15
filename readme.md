# 🚀 Remote Dev Control (RDC)

**A sua estação de trabalho desktop, agora no seu bolso.**

O **Remote Dev Control (RDC)** é uma plataforma *self-hosted* de código aberto projetada para desenvolvedores que precisam de flexibilidade. Ele permite que você controle seus projetos, edite arquivos, gerencie repositórios Git e execute comandos de terminal diretamente do seu dispositivo móvel, sem depender de ferramentas de acesso remoto pesadas como AnyDesk ou TeamViewer.

> **Aviso de Fork/Créditos:** Este projeto é um fork/branch expandido do incrível [MiMo Code](https://github.com/mimo-ai/mimocode). Agradecimentos especiais à equipe por fornecer a infraestrutura robusta do assistente de IA de linha de comando. Nós adaptamos e integramos o MiMo Code nativamente para permitir controle inteligente de código remoto via mobile.

---

## 🌟 Destaques do Projeto

- **⚡ Agente Desktop de Alta Performance**: Construído com **FastAPI** e **Python**, garantindo respostas rápidas e baixo consumo de recursos.
- **📱 App Mobile Nativo**: Interface fluida desenvolvida em **Flutter**, otimizada para produtividade em telas pequenas.
- **🔐 Segurança em Primeiro Lugar**: Comunicação criptografada via **HTTPS (TLS/SSL)** e autenticação robusta via **JWT**.
- **💻 Terminal em Tempo Real**: Sessões PTY reais com suporte a cores ANSI e persistência.
- **🤖 Integração Nativa MiMo Code**: Assistente inteligente de IA (destaque para o `mimo-auto` gratuito) operando nos seus arquivos locais com acompanhamento e logs detalhados em tempo real.
- **🌐 Preview Web**: Visualize suas aplicações web em desenvolvimento diretamente no celular.

---

## 🏗️ Arquitetura do Sistema

O RDC é dividido em três componentes principais que operam em conjunto:

1.  **Agente Desktop (`/rdc/agent`)**: Roda na sua máquina principal (Windows/Linux). Gerencia o sistema de arquivos, executa processos, invoca o CLI do MiMo e expõe a API.
2.  **App Mobile (`/rdc/mobile`)**: A sua interface de controle. Conecta-se ao agente para fornecer uma experiência de IDE mobile e delegar tarefas ao assistente de IA.

---

## 🚀 Guia de Instalação e Configuração

### 1. Preparando o Agente Desktop (Python)

**Pré-requisitos:** Python 3.11+ e Node.js/npm.

1.  Navegue até a pasta do agente:
    ```bash
    cd rdc/agent
    ```
2.  Crie e ative um ambiente virtual:
    ```bash
    # Windows
    python -m venv .venv
    .\.venv\Scripts\activate

    # Linux/macOS
    python3 -m venv .venv
    source .venv/bin/activate
    ```
3.  Instale as dependências:
    ```bash
    pip install -r requirements.txt
    ```
4.  Configure as variáveis de ambiente:
    - Copie o arquivo `.env.example` para `.env`.
    - Defina sua `AGENT_PASSWORD` (mínimo 4 caracteres).
5.  Instale o CLI Oficial do MiMo Code globalmente:
    ```bash
    npm install -g @mimo-ai/cli
    ```
6.  Faça login no MiMo (necessário para liberar o plano gratuito MiMo Auto):
    ```bash
    mimo auth login
    ```
    *Selecione "MiMo Auto (free)" e siga as instruções no navegador.*
7.  Inicie o Agente:
    - **Via Terminal (CLI):** `python main.py`

### 2. Preparando o App Mobile (Flutter)

**Pré-requisitos:** Flutter SDK configurado.

1.  Navegue até a pasta do app:
    ```bash
    cd rdc/mobile
    ```
2.  Instale as dependências do Flutter:
    ```bash
    flutter pub get
    ```
3.  Execute o aplicativo:
    - Conecte seu dispositivo físico ou inicie um emulador.
    - Execute: `flutter run`

---

## ✨ Recursos Adicionados Recentemente (Integração MiMo)

- **MiMo Auto Nativo:** Acesso ao LLM autônomo totalmente **gratuito**, que entra em ação sem necessidade de configuração de API keys próprias (requer apenas login rápido pela TUI do mimo).
- **UI do App Aprimorada:** O App Mobile (Flutter) agora destaca visualmente o modelo MiMo Auto (com badges e sem campos obrigatórios de chave) e faz sua pré-seleção lógica caso nenhuma API Key tenha sido adicionada, melhorando muito a usabilidade de onboarding.
- **Streaming de Logs Detalhado (Stderr/Stdout):** O backend em Python agora intercepta e emite todos os passos em background do assistente. Erros críticos ou lógicas internas do MiMo-Code são transmitidas em tempo real para o usuário do celular, garantindo total transparência do que está ocorrendo na máquina remota.
- **Auto-Fallbacks:** Ajustes nas ferramentas internas da TUI do CLI para sempre dar prioridade em invocar os modelos gratuitos de forma "zero-config", diminuindo o tempo de setup do agente de inteligência.

---

## 🛠️ Funcionalidades Detalhadas

| Módulo | Descrição | Tecnologia |
| :--- | :--- | :--- |
| **Dashboard** | Visão geral do hardware (CPU, RAM, Disco) e uptime. | `psutil` |
| **Explorador** | Navegação incremental no sistema de arquivos, CRUD e Upload. | `os`, `shutil` |
| **Editor** | Edição de código com Syntax Highlight para múltiplas linguagens. | `flutter_highlight` |
| **Terminal** | Terminal interativo completo com suporte a múltiplas sessões. | `pywinpty` / `pty` |
| **Git** | Interface para status, commit, push, pull e troca de branches. | `GitPython` |
| **Mimo Agent** | Interface móvel para invocação inteligente de comandos no código, visualização de diffs em tempo real e aprovação remota. | `mimo-code`, `asyncio` |
| **Preview** | Visualização de apps web rodando em portas locais (Vite, React, etc). | `httpx` Proxy |

---

## 🔒 Segurança

O RDC gera automaticamente certificados TLS auto-assinados na primeira execução para garantir que todos os dados trafegados entre seu celular e computador estejam protegidos. A autenticação utiliza tokens JWT com rotação automática, garantindo que apenas você tenha acesso à sua máquina.

---

## 🤝 Contribuição

Contribuições são o que tornam a comunidade open source um lugar incrível para aprender, inspirar e criar. Qualquer contribuição que você fizer será **muito apreciada**.

1. Faça um Fork do projeto
2. Crie uma Branch para sua funcionalidade (`git checkout -b feature/AmazingFeature`)
3. Insira suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Faça o Push da Branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais informações.

---
Desenvolvido com ❤️ para a comunidade de desenvolvedores. Agradecimento especial aos engenheiros do MiMo Code por criar a base da IA.
