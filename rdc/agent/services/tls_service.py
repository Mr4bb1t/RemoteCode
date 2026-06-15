"""
RDC Agent — Geração de certificado TLS auto-assinado
"""
from __future__ import annotations

from pathlib import Path

import trustme


def ensure_tls_cert(cert_path: Path, key_path: Path) -> None:
    """Gera certificado TLS auto-assinado se não existir."""
    cert_path.parent.mkdir(parents=True, exist_ok=True)
    key_path.parent.mkdir(parents=True, exist_ok=True)

    if cert_path.exists() and key_path.exists():
        return  # Já existe, não regenerar

    ca = trustme.CA()
    server_cert = ca.issue_cert("localhost", "127.0.0.1", "0.0.0.0")

    # Salvar certificado e chave privada
    server_cert.private_key_pem.write_to_path(str(key_path))

    with open(str(cert_path), "wb") as f:
        for blob in server_cert.cert_chain_pems:
            f.write(blob.bytes())

    print(f"[RDC] Certificado TLS gerado em: {cert_path}")
    print(f"[RDC] Chave privada em: {key_path}")
    print("[RDC] AVISO: Certificado auto-assinado. Aceite-o no seu dispositivo móvel.")
