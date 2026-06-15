import tkinter as tk
from tkinter import ttk, messagebox
import threading
import socket
import os
import sys
import uvicorn
from dotenv import set_key, load_dotenv
from pathlib import Path

# Configurações de ambiente
BASE_DIR = Path(__file__).resolve().parent
env_path = BASE_DIR / ".env"

def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

class AgentGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("RDC Agent")
        self.root.geometry("450x360")
        self.root.resizable(False, False)
        
        # Estilo
        style = ttk.Style()
        style.theme_use('clam')
        style.configure("TButton", padding=6, font=('Arial', 10))
        style.configure("TLabel", font=('Arial', 10))
        
        # Carregar variáveis de ambiente
        load_dotenv(env_path)
        self.password = os.environ.get("AGENT_PASSWORD", "")
        
        self.is_running = False
        self.server_thread = None
        
        # Checar se a senha está definida (e não é a padrão)
        if not self.password or self.password in ["rdc_change_me", "minha_senha_segura"]:
            self.show_setup_screen()
        else:
            self.show_main_screen()

    def show_setup_screen(self):
        self.clear_window()
        
        frame = ttk.Frame(self.root, padding=20)
        frame.pack(fill=tk.BOTH, expand=True)
        
        lbl_title = ttk.Label(frame, text="Bem-vindo ao RDC Agent", font=("Arial", 16, "bold"))
        lbl_title.pack(pady=(10, 20))
        
        lbl_desc = ttk.Label(
            frame, 
            text="Para garantir a segurança da sua conexão,\ndefina uma senha para conectar seu\ndispositivo móvel a este computador:", 
            justify=tk.CENTER
        )
        lbl_desc.pack(pady=10)
        
        self.pwd_var = tk.StringVar()
        entry_pwd = ttk.Entry(frame, textvariable=self.pwd_var, show="*", width=30, font=('Arial', 12))
        entry_pwd.pack(pady=10)
        entry_pwd.focus()
        
        btn_save = ttk.Button(frame, text="Salvar Senha", command=self.save_password)
        btn_save.pack(pady=20)

    def save_password(self):
        pwd = self.pwd_var.get().strip()
        if len(pwd) < 4:
            messagebox.showerror("Erro", "A senha deve ter pelo menos 4 caracteres.")
            return
            
        # Cria ou atualiza o arquivo .env
        if not env_path.exists():
            with open(env_path, "w", encoding="utf-8") as f:
                f.write(f"AGENT_PASSWORD={pwd}\n")
        else:
            set_key(str(env_path), "AGENT_PASSWORD", pwd)
            
        self.password = pwd
        os.environ["AGENT_PASSWORD"] = pwd
        
        # Forçar atualização nas settings do config.py se ele já foi importado
        from config import get_settings
        get_settings.cache_clear()
        
        messagebox.showinfo("Sucesso", "Senha configurada com sucesso!")
        self.show_main_screen()

    def show_main_screen(self):
        self.clear_window()
        
        frame = ttk.Frame(self.root, padding=20)
        frame.pack(fill=tk.BOTH, expand=True)
        
        lbl_title = ttk.Label(frame, text="Painel do Agente RDC", font=("Arial", 16, "bold"))
        lbl_title.pack(pady=(0, 15))
        
        # Frame de Informações
        frame_info = ttk.LabelFrame(frame, text="Informações de Conexão", padding=15)
        frame_info.pack(fill=tk.X, pady=10)
        
        ip = get_local_ip()
        from config import get_settings
        port = get_settings().port
        
        # URL
        ttk.Label(frame_info, text="URL do Agente:").grid(row=0, column=0, sticky=tk.W, pady=5, padx=5)
        self.url_entry = ttk.Entry(frame_info, width=32)
        self.url_entry.insert(0, f"https://{ip}:{port}")
        self.url_entry.config(state="readonly")
        self.url_entry.grid(row=0, column=1, sticky=tk.W, padx=5)
        
        # Senha
        ttk.Label(frame_info, text="Sua Senha:").grid(row=1, column=0, sticky=tk.W, pady=5, padx=5)
        pwd_entry = ttk.Entry(frame_info, width=28, show="*")
        pwd_entry.insert(0, self.password)
        pwd_entry.config(state="readonly")
        pwd_entry.grid(row=1, column=1, sticky=tk.W, padx=5)
        
        # Adicionar botão para mostrar/ocultar senha
        self.show_pwd = False
        def toggle_pwd():
            self.show_pwd = not self.show_pwd
            pwd_entry.config(show="" if self.show_pwd else "*")
            
        ttk.Button(frame_info, text="Ver", width=4, command=toggle_pwd).grid(row=1, column=2, padx=5)
        
        # Opções
        frame_tunnel = ttk.Frame(frame)
        frame_tunnel.pack(fill=tk.X, pady=(5, 0))
        self.use_tunnel_var = tk.BooleanVar(value=False)
        chk_tunnel = ttk.Checkbutton(frame_tunnel, text="Acesso Global (Cloudflare)", variable=self.use_tunnel_var)
        chk_tunnel.pack(side=tk.LEFT)
        btn_cf = ttk.Button(frame_tunnel, text="⚙️ Configurar Fixo", width=16, command=self.config_cloudflare)
        btn_cf.pack(side=tk.RIGHT)
        
        # Status e Ações
        self.lbl_status = ttk.Label(frame, text="Status: Aguardando...", foreground="red", font=("Arial", 12, "bold"))
        self.lbl_status.pack(pady=10)
        
        self.btn_toggle = ttk.Button(frame, text="Iniciar Servidor", command=self.toggle_server, width=20)
        self.btn_toggle.pack(pady=5)

    def config_cloudflare(self):
        cf_token = os.environ.get("CF_TUNNEL_TOKEN", "")
        cf_url = os.environ.get("CF_TUNNEL_URL", "")
        
        top = tk.Toplevel(self.root)
        top.title("Configurar Cloudflare Fixo")
        top.geometry("380x260")
        top.resizable(False, False)
        
        ttk.Label(top, text="Se você possui um túnel permanente no Cloudflare Zero Trust,\ninsira o Token abaixo para manter a mesma URL sempre.", justify=tk.CENTER).pack(pady=(10, 10))
        
        ttk.Label(top, text="Cloudflare Tunnel Token:").pack(anchor=tk.W, padx=20)
        entry_token = ttk.Entry(top, width=50)
        entry_token.insert(0, cf_token)
        entry_token.pack(padx=20, pady=5)
        
        ttk.Label(top, text="URL do Túnel (ex: https://meu-app.com):").pack(anchor=tk.W, padx=20, pady=(10,0))
        entry_url = ttk.Entry(top, width=50)
        entry_url.insert(0, cf_url)
        entry_url.pack(padx=20, pady=5)
        
        def save():
            token = entry_token.get().strip()
            url = entry_url.get().strip()
            if not env_path.exists():
                with open(env_path, "w", encoding="utf-8") as f:
                    f.write("\n")
            set_key(str(env_path), "CF_TUNNEL_TOKEN", token)
            set_key(str(env_path), "CF_TUNNEL_URL", url)
            os.environ["CF_TUNNEL_TOKEN"] = token
            os.environ["CF_TUNNEL_URL"] = url
            messagebox.showinfo("Sucesso", "Configuração salva! Use a opção de Acesso Global para iniciar.")
            top.destroy()
            
        ttk.Button(top, text="Salvar", command=save).pack(pady=15)

    def toggle_server(self):
        if not self.is_running:
            self.start_server()
        else:
            messagebox.showinfo("Aviso", "Para parar o servidor, simplesmente feche esta janela.")

    def start_server(self):
        from main import app
        from config import get_settings
        from services.tls_service import ensure_tls_cert
        
        settings = get_settings()
        ensure_tls_cert(settings.ssl_certfile, settings.ssl_keyfile)
        
        def run_uvicorn():
            # Iniciar uvicorn no modo programático desabilita o reload
            uvicorn.run(
                app,
                host=settings.host,
                port=settings.port,
                ssl_certfile=str(settings.ssl_certfile),
                ssl_keyfile=str(settings.ssl_keyfile),
                log_level="error"
            )
            
        self.server_thread = threading.Thread(target=run_uvicorn, daemon=True)
        self.server_thread.start()
        
        self.is_running = True
        self.lbl_status.config(text="Status: Online e Pronto", foreground="green")
        self.btn_toggle.config(state="disabled", text="Servidor Rodando")
        
        if self.use_tunnel_var.get():
            threading.Thread(target=self._start_tunnel, args=(settings.port,), daemon=True).start()

    def _start_tunnel(self, port):
        self.lbl_status.config(text="Status: Iniciando Túnel...", foreground="orange")
        cf_token = os.environ.get("CF_TUNNEL_TOKEN", "").strip()
        cf_url = os.environ.get("CF_TUNNEL_URL", "").strip()
        try:
            import pycloudflared
            from pycloudflared.util import get_info, download
            from pathlib import Path
            import subprocess
            import re
            
            info = get_info()
            if not Path(info.executable).exists():
                download(info)
                
            if cf_token:
                args = [
                    info.executable,
                    "tunnel",
                    "--no-autoupdate",
                    "run",
                    "--token",
                    cf_token
                ]
                proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, encoding="utf-8")
                
                if cf_url:
                    self.url_entry.config(state="normal")
                    self.url_entry.delete(0, tk.END)
                    self.url_entry.insert(0, cf_url)
                    self.url_entry.config(state="readonly")
                    
                self.lbl_status.config(text="Status: Túnel Fixo Ativo", foreground="green")
            else:
                args = [
                    info.executable,
                    "tunnel",
                    "--protocol",
                    "http2",
                    "--url",
                    f"https://127.0.0.1:{port}",
                    "--no-tls-verify"
                ]
                
                proc = subprocess.Popen(
                    args,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    encoding="utf-8"
                )
                
                url_pattern = re.compile(r"(https?://\S+\.trycloudflare\.com)")
                tunnel_url = ""
                for _ in range(50):
                    line = proc.stderr.readline()
                    if not line:
                        break
                    match = url_pattern.search(line)
                    if match:
                        tunnel_url = match.group(1)
                        break
                        
                if tunnel_url:
                    self.url_entry.config(state="normal")
                    self.url_entry.delete(0, tk.END)
                    self.url_entry.insert(0, tunnel_url)
                    self.url_entry.config(state="readonly")
                    self.lbl_status.config(text="Status: Túnel Ativo", foreground="green")
                else:
                    self.lbl_status.config(text="Status: Falha no Túnel", foreground="red")
                    proc.terminate()
        except ImportError:
            messagebox.showerror("Erro", "pycloudflared não instalado. Rode: pip install pycloudflared")
            self.lbl_status.config(text="Status: Servidor Local (Sem Túnel)", foreground="green")
        except Exception as e:
            messagebox.showerror("Erro Túnel", f"Erro ao iniciar túnel: {e}")
            self.lbl_status.config(text="Status: Falha no Túnel", foreground="red")

    def clear_window(self):
        for widget in self.root.winfo_children():
            widget.destroy()

def start_gui():
    root = tk.Tk()
    app = AgentGUI(root)
    
    # Fechar graciosamente
    def on_closing():
        root.destroy()
        sys.exit(0)
        
    root.protocol("WM_DELETE_WINDOW", on_closing)
    root.mainloop()

if __name__ == "__main__":
    start_gui()
