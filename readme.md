# 🚀 Remote Dev Control (RDC)

**A sua estação de trabalho desktop, agora no seu bolso.**

O **Remote Dev Control (RDC)** é uma plataforma *self-hosted* de código aberto projetada para desenvolvedores que precisam de flexibilidade. Ele permite que você controle seus projetos, edite arquivos, gerencie repositórios Git e execute comandos de terminal diretamente do seu dispositivo móvel, sem depender de ferramentas de acesso remoto pesadas como AnyDesk ou TeamViewer.

---

## 🌟 Destaques do Projeto

- **⚡ Agente Desktop de Alta Performance**: Construído com **FastAPI** e **Python**, garantindo respostas rápidas e baixo consumo de recursos.
- **📱 App Mobile Nativo**: Interface fluida desenvolvida em **Flutter**, otimizada para produtividade em telas pequenas.
- **🔐 Segurança em Primeiro Lugar**: Comunicação criptografada via **HTTPS (TLS/SSL)** e autenticação robusta via **JWT**.
- **💻 Terminal em Tempo Real**: Sessões PTY reais com suporte a cores ANSI e persistência.
- **🤖 Integração com IA (Antigravity)**: Assistente inteligente integrado para auxiliar no desenvolvimento via comandos de voz ou texto.
- **🌐 Preview Web**: Visualize suas aplicações web em desenvolvimento diretamente no celular.

---

## 🏗️ Arquitetura do Sistema

O RDC é dividido em dois componentes principais que se comunicam via rede local (ou túneis):

1.  **Agente Desktop (`/agent`)**: Roda na sua máquina principal (Windows/Linux). Gerencia o sistema de arquivos, executa processos e expõe a API.
2.  **App Mobile (`/mobile`)**: A sua interface de controle. Conecta-se ao agente para fornecer uma experiência de IDE mobile.

---

## 🚀 Guia de Inalação e Configuração

### 1. Preparando o Agente Desktop (Python)

**Pré-requisitos:** Python 3.11 ou superior instalado.

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
    - *(Opcional)* Configure sua chave de API para o módulo Antigravity.
5.  Inicie o Agente:
    - **Com Interface Gráfica (GUI):** `python gui.py`
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

## 🛠️ Funcionalidades Detalhadas

| Módulo | Descrição | Tecnologia |
| :--- | :--- | :--- |
| **Dashboard** | Visão geral do hardware (CPU, RAM, Disco) e uptime. | `psutil` |
| **Explorador** | Navegação incremental no sistema de arquivos, CRUD e Upload. | `os`, `shutil` |
| **Editor** | Edição de código com Syntax Highlight para múltiplas linguagens. | `flutter_highlight` |
| **Terminal** | Terminal interativo completo com suporte a múltiplas sessões. | `pywinpty` / `pty` |
| **Git** | Interface para status, commit, push, pull e troca de branches. | `GitPython` |
| **Testes** | Execução e acompanhamento de testes (Pytest, Jest, etc). | `subprocess` |
| **Preview** | Visualização de apps web rodando em portas locais (Vite, React, etc). | `httpx` Proxy |
| **Antigravity** | Assistente de IA para automação de tarefas de código. | `litellm` |

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
Desenvolvido com ❤️ para a comunidade de desenvolvedores.
