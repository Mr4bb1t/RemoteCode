# 🚀 Remote Dev Control (RDC)

**A sua estação de trabalho desktop, agora no seu bolso.**

O **Remote Dev Control (RDC)** é uma ferramenta completa e independente, focada em transformar seu dispositivo móvel no controle remoto definitivo do seu ambiente de desenvolvimento desktop. Ele permite que você assuma as rédeas dos seus projetos, edite arquivos com syntax highlight, gerencie repositórios Git, monitore o desempenho da sua máquina, e execute comandos de terminal persistentes diretamente da tela do celular, sem precisar depender de softwares de acesso remoto convencionais pesados (como AnyDesk ou TeamViewer).

> **Agradecimentos Especiais:** Embora o RDC seja uma ferramenta própria com um grande leque de funcionalidades, nós integramos nativamente e utilizamos o incrível [MiMo Code](https://github.com/mimo-ai/mimocode) como nossa sub-ferramenta oficial para inteligência artificial autônoma. Agradecemos profundamente à equipe do MiMo por criar essa fundação robusta de assistente CLI que habilitou as capacidades de IA avançadas do RDC!

---

## 🌟 Destaques do Projeto

- **⚡ Agente Desktop Próprio e Leve**: Construído do zero com **FastAPI** e **Python**, focando em garantir respostas instantâneas, WebSocket contínuo e baixo consumo de CPU/RAM.
- **📱 App Mobile Nativo e Rico**: Uma interface rica, dinâmica e ultra fluida desenvolvida em **Flutter**, otimizada ergonomicamente para gerenciar o desktop via mobile.
- **🔐 Segurança e Privacidade em Primeiro Lugar**: Arquitetura self-hosted com tráfego 100% criptografado via **HTTPS (TLS/SSL)** e autenticação robusta via tokens **JWT** auto-rotativos.
- **💻 Terminal PTY e Logs de Processos**: Sessões de shell persistentes com cores ANSI reais. Além disso, conta com um gerenciador visual avançado (Taskkill/Processos) na aba de Logs para comandos da sua stack.
- **🤖 Integração MiMo Autônoma**: Delegação de tarefas complexas de código a IA usando o CLI oficial do MiMo Code de forma invisível, com aprovação e visualização de diffs remoto via celular.
- **🌐 Preview Dinâmico**: Renderize de forma adaptada as aplicações web locais rodando em portas locais (React, Vite, Next.js) diretamente na tela do seu dispositivo mobile.

---

## 🏗️ Arquitetura do Sistema

O RDC opera através da integração cliente-servidor de dois ecossistemas:

1.  **Agente Desktop (`/rdc/agent`)**: O servidor que você roda na máquina alvo (Windows, Linux, macOS). É o "motor" que orquestra leitura de arquivos, execução em terminal nativo, monitoramento, proxy de portas para preview, e invoca sub-ferramentas CLI.
2.  **App Mobile (`/rdc/mobile`)**: O cliente principal. Conecta-se diretamente via IP/Host na sua rede (ou VPN) para prover uma interface tátil, limpa e responsiva de IDE.

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
5.  *(Opcional, porém Recomendado)* Instale a sub-ferramenta de IA (MiMo Code):
    ```bash
    npm install -g @mimo-ai/cli
    mimo auth login
    ```
6.  Inicie o Agente RDC:
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
    - Conecte seu celular físico, inicie o emulador, ou compile a APK.
    - Execute: `flutter run`

---

## 🛠️ Funcionalidades e Sub-ferramentas

| Módulo | Funcionalidade Principal | Tecnologia Envolvida |
| :--- | :--- | :--- |
| **Dashboard** | Visão geral do hardware em tempo real (CPU, RAM, Disco) e uptime da máquina. | Python `psutil` |
| **Explorador** | Navegação rápida no File System, edição em lote, criação/remoção e Upload/Download. | Python `os`, `shutil` |
| **Editor de Código** | Editor nativo com Syntax Highlight customizável. Rolagem fluida e não-quebra-linha. | `flutter_highlight` |
| **Terminal & Processos** | Terminais iterativos múltiplos e painel "Logs" com seletores rápidos e botões Context-Aware. | `pywinpty` / `subprocess` |
| **Git UI** | Abstração da ferramenta git para Commits fáceis, monitoramento de status e push remotos. | `GitPython` |
| **Assistente de IA** | Sub-ferramenta integrada capaz de sugerir e aplicar refatorações complexas autonomamente. | `mimo-code` CLI |
| **Preview Web** | Adaptação e proxy de portas (como localhost:3000) para visualização renderizada no Mobile. | `httpx` Proxy Dinâmico |

---

## 🔒 Segurança Garantida

A segurança no Remote Dev Control é tratada desde a primeira rodada do servidor. O RDC gera automaticamente chaves locais e um certificado TLS (auto-assinado) exclusivo, para bloquear tráfego plaintext em redes Wi-Fi e garantir encriptação ponta a ponta. Sessões mobile só são validadas através de chaves estritas (Tokens JWT gerados no app após validação de senha). 

---

## 🤝 Contribuição

Este projeto visa facilitar absurdamente a vida do programador moderno. Contribuições, ideias visuais, issues e melhorias de performance são **muito apreciadas**!

1. Faça um Fork do projeto
2. Crie uma Branch para a sua nova Feature (`git checkout -b feature/FuncaoTop`)
3. Commit suas adições (`git commit -m 'feat: Add FuncaoTop'`)
4. Faça o Push (`git push origin feature/FuncaoTop`)
5. Abra um Pull Request e vamos conversar!

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais informações.

---
Desenvolvido com ❤️ para empoderar a comunidade dev que nunca desliga.
Agradecimentos ao [MiMo Code](https://github.com/mimo-ai/mimocode) pela excelente suite que utilizamos como sub-ferramenta LLM.
