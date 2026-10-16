#!/usr/bin/env python3
"""
Notificador de Incidentes Fail2ban para Telegram
Autor: Rafael Soje (https://github.com/rafaelsoje)
Especialização: Segurança da Informação & DevSecOps

Gera relatórios forenses estruturados quando o Fail2ban bloqueia um IP:
- Extrai tentativas de payloads HTTP em logs do Nginx
- Identifica nomes de usuários forçados em ataques de força bruta SSH
- Informa se o IP foi bloqueado na borda (Cloudflare WAF)
"""

import os
from pathlib import Path
import re
import subprocess
import sys

TELEGRAM_SCRIPT = Path(__file__).resolve().parent / "hids" / "chat-telegram.sh"
DEFAULT_NGINX_LOGS = [
    Path("/var/log/nginx/access.log"),
    Path("/var/log/nginx/error.log")
]


def extract_nginx_probes(ip: str, limit: int = 5):
    custom_logs = os.environ.get("NGINX_ACCESS_LOGS", "")
    if custom_logs:
        logs = [Path(p.strip()) for p in custom_logs.split(",") if p.strip()]
    else:
        logs = DEFAULT_NGINX_LOGS

    probes = []
    seen = set()
    pattern = re.compile(r'"([A-Z]+ [^"]+)" (\d{3})')

    for log_path in logs:
        if not log_path.exists():
            continue
        try:
            with open(log_path, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 2097152), os.SEEK_SET)  # Últimos 2 MB
                lines = f.read().decode("utf-8", errors="ignore").splitlines()

            for line in reversed(lines):
                if line.startswith(f"{ip} ") or f" [client {ip}]" in line:
                    m = pattern.search(line)
                    if m:
                        req, status = m.group(1), m.group(2)
                        item = f"{req} [HTTP {status}]"
                        if item not in seen:
                            seen.add(item)
                            probes.append(item)
                            if len(probes) >= limit:
                                break
        except Exception:
            continue
        if len(probes) >= limit:
            break
    return probes


def extract_ssh_details(ip: str):
    try:
        cmd = ["journalctl", "-u", "ssh", "-u", "sshd", "--since=-1h", "-o", "cat"]
        out = subprocess.run(cmd, capture_output=True, text=True, errors="ignore").stdout
        users = set()
        for line in out.splitlines():
            if ip in line:
                m_user = re.search(r'(?:user|for)\s+([a-zA-Z0-9_\-\.]+)\s+from', line)
                if m_user:
                    users.add(m_user.group(1))
        return sorted(list(users))
    except Exception:
        return []


def main():
    if len(sys.argv) < 5:
        sys.exit(0)

    action = sys.argv[1]  # 'ban'
    if action != "ban":
        sys.exit(0)

    jail = sys.argv[2]
    ip = sys.argv[3]
    try:
        duration = int(sys.argv[4])
    except ValueError:
        duration = 3600

    failures = sys.argv[5] if len(sys.argv) > 5 else None
    cf_blocked = (len(sys.argv) > 6 and sys.argv[6] == "1")

    # Formatação amigável do tempo de bloqueio
    h = duration // 3600
    m = (duration % 3600) // 60
    if h >= 1 and m == 0:
        t_str = f"{h}h"
    elif h >= 1:
        t_str = f"{h}h {m}m"
    else:
        t_str = f"{duration // 60}m"

    lines = [
        "🛡️ [Fail2ban Security Alert] IP Bloqueado",
        "",
        f"📍 IP: {ip}",
    ]
    if cf_blocked:
        lines.append("☁️ Borda: Bloqueado no Cloudflare Edge (WAF Rule)")

    if "modsec" in jail.lower():
        lines.append(f"🏷️ Tipo: Ataque Bloqueado pelo WAF / ModSecurity ({jail})")
        lines.append(f"⏱️ Duração do Ban: {t_str}")
        if failures:
            lines.append(f"⚠️ Tentativas registradas: {failures} ocorrências")

        probes = extract_nginx_probes(ip, limit=5)
        if probes:
            lines.append("")
            lines.append("🔍 Requisições detectadas:")
            for p in probes:
                lines.append(f" • {p}")
        else:
            lines.append("\n🔍 Motivo: Payload malicioso interceptado pelas regras OWASP CRS.")

    elif "nginx" in jail.lower():
        lines.append(f"🏷️ Tipo: Sondagem de Rotas Sensíveis ({jail})")
        lines.append(f"⏱️ Duração do Ban: {t_str}")
        if failures:
            lines.append(f"⚠️ Tentativas registradas: {failures} ocorrências")

        probes = extract_nginx_probes(ip, limit=5)
        if probes:
            lines.append("")
            lines.append("🔍 Rotas acessadas pelo scanner:")
            for p in probes:
                lines.append(f" • {p}")
        else:
            lines.append("\n🔍 Motivo: Múltiplas requisições a caminhos proibidos (.env, .git, etc.).")

    elif "ssh" in jail.lower():
        lines.append(f"🏷️ Tipo: Força Bruta SSH ({jail})")
        lines.append(f"⏱️ Duração do Ban: {t_str}")
        if failures:
            lines.append(f"⚠️ Falhas de autenticação: {failures}")

        users = extract_ssh_details(ip)
        if users:
            lines.append(f"👤 Usuários visados no ataque: {', '.join(users)}")
    else:
        lines.append(f"🏷️ Tipo: Regra defensiva disparada ({jail})")
        lines.append(f"⏱️ Duração: {t_str}")

    msg = "\n".join(lines)

    if TELEGRAM_SCRIPT.is_file() and os.access(TELEGRAM_SCRIPT, os.X_OK):
        try:
            subprocess.run([str(TELEGRAM_SCRIPT), msg], timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass


if __name__ == "__main__":
    main()
