#!/usr/bin/env python3
"""
Bloqueador em Camada Dupla: Fail2ban + Nginx RealIP Map + Cloudflare Edge
Autor: Rafael Soje (https://github.com/rafaelsoje)
Especialização: Segurança da Informação & DevSecOps

Bloqueia invasores e scanners tanto na camada de aplicação (Nginx RealIP map)
quanto na borda (Cloudflare Firewall Access Rules) preservando a performance do host.
"""

import fcntl
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request

STATE_FILE = Path(os.environ.get("F2B_STATE_FILE", "/var/lib/fail2ban/nginx-probes.json"))
MAP_FILE = Path(os.environ.get("F2B_MAP_FILE", "/etc/nginx/fail2ban/blocked.map"))
NOTIFY_SCRIPT = Path(__file__).resolve().parent / "f2b-telegram-notify.py"

# Carrega variáveis de ambiente ou config.env
CONFIG_ENV = Path(__file__).resolve().parent / "config.env"
if CONFIG_ENV.exists():
    for line in CONFIG_ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def get_cf_config():
    cf_email = os.environ.get("CLOUDFLARE_EMAIL")
    cf_key = os.environ.get("CLOUDFLARE_API_KEY")
    zone_id = os.environ.get("CLOUDFLARE_ZONE_ID")

    if cf_email and cf_key and zone_id:
        return {"email": cf_email, "key": cf_key, "zone_id": zone_id}
    return None


def cf_ban(ip: str, jail: str):
    cfg = get_cf_config()
    if not cfg:
        return None

    zone_id = cfg["zone_id"]
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/firewall/access_rules/rules"
    headers = {
        "X-Auth-Email": cfg["email"],
        "X-Auth-Key": cfg["key"],
        "Content-Type": "application/json"
    }
    payload = json.dumps({
        "mode": "block",
        "configuration": {"target": "ip", "value": str(ip)},
        "notes": f"Fail2ban auto-ban: {jail}"
    }).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            if res.get("success"):
                return res.get("result", {}).get("id")
    except Exception as e:
        sys.stderr.write(f"[AVISO] Cloudflare ban erro para {ip}: {e}\n")
    return None


def cf_unban(rule_id: str):
    if not rule_id:
        return
    cfg = get_cf_config()
    if not cfg:
        return

    zone_id = cfg["zone_id"]
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/firewall/access_rules/rules/{rule_id}"
    headers = {
        "X-Auth-Email": cfg["email"],
        "X-Auth-Key": cfg["key"],
        "Content-Type": "application/json"
    }
    try:
        req = urllib.request.Request(url, headers=headers, method="DELETE")
        with urllib.request.urlopen(req, timeout=10) as resp:
            pass
    except Exception as e:
        sys.stderr.write(f"[AVISO] Cloudflare unban erro para rule_id {rule_id}: {e}\n")


def reload_nginx():
    if not MAP_FILE.parent.exists():
        MAP_FILE.parent.mkdir(parents=True, exist_ok=True)

    cmd = ["nginx", "-t"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        subprocess.run(["systemctl", "reload", "nginx"], check=False)
    else:
        sys.stderr.write(f"[ERRO] Sintaxe do Nginx inválida ao recarregar: {res.stderr}\n")


def write_nginx_map(state: dict):
    MAP_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp_file = MAP_FILE.with_suffix(".tmp")
    now = time.time()

    lines = ["# Arquivo gerado automaticamente por Fail2ban Nginx-Block\n"]
    for ip, data in state.items():
        if data.get("expires_at", 0) > now:
            lines.append(f"{ip} 1;\n")

    temp_file.write_text("".join(lines), encoding="utf-8")
    temp_file.replace(MAP_FILE)
    reload_nginx()


def load_state():
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_state(state: dict):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp_file = STATE_FILE.with_suffix(".tmp")
    temp_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    temp_file.replace(STATE_FILE)


def ban_ip(ip: str, bantime: int, jail: str, failures: str):
    state = load_state()
    cf_rule_id = cf_ban(ip, jail)

    state[ip] = {
        "banned_at": time.time(),
        "expires_at": time.time() + bantime,
        "jail": jail,
        "failures": failures,
        "cf_rule_id": cf_rule_id
    }
    save_state(state)
    write_nginx_map(state)

    if NOTIFY_SCRIPT.exists() and os.access(NOTIFY_SCRIPT, os.X_OK):
        cf_flag = "1" if cf_rule_id else "0"
        subprocess.run([
            str(NOTIFY_SCRIPT), "ban", jail, ip, str(bantime), str(failures), cf_flag
        ], check=False)


def unban_ip(ip: str):
    state = load_state()
    if ip in state:
        cf_rule_id = state[ip].get("cf_rule_id")
        if cf_rule_id:
            cf_unban(cf_rule_id)
        del state[ip]
        save_state(state)
        write_nginx_map(state)


def main():
    if len(sys.argv) < 2:
        print("Uso:")
        print("  f2b-nginx-cloudflare-block.py ban <ip> <bantime_segundos> <jail> [failures]")
        print("  f2b-nginx-cloudflare-block.py unban <ip>")
        print("  f2b-nginx-cloudflare-block.py sync")
        print("  f2b-nginx-cloudflare-block.py clear")
        sys.exit(1)

    action = sys.argv[1].lower()

    if action == "ban" and len(sys.argv) >= 5:
        ip = sys.argv[2]
        bantime = int(sys.argv[3])
        jail = sys.argv[4]
        failures = sys.argv[5] if len(sys.argv) > 5 else "1"
        ban_ip(ip, bantime, jail, failures)
    elif action == "unban" and len(sys.argv) >= 3:
        ip = sys.argv[2]
        unban_ip(ip)
    elif action == "sync":
        write_nginx_map(load_state())
    elif action == "clear":
        write_nginx_map({})


if __name__ == "__main__":
    main()
