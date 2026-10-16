#!/usr/bin/env python3
"""
Sincronizador Automático: AbuseIPDB -> Cloudflare WAF IP Lists
Autor: Rafael Soje (https://github.com/rafaelsoje)
Especialização: Segurança da Informação & DevSecOps

Consulta a API v2 do AbuseIPDB para obter a lista consolidada de IPs maliciosos
(com pontuação de abuso >= 90%) e sincroniza em lote na lista de bloqueio
de borda (Custom Rules IP List) do Cloudflare WAF.
"""

import datetime
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zoneinfo

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Carrega variáveis de ambiente ou arquivo config.env local
CONFIG_ENV = Path(__file__).resolve().parent / "config.env"
if CONFIG_ENV.exists():
    for line in CONFIG_ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

TELEGRAM_SCRIPT = Path(__file__).resolve().parent / "hids" / "chat-telegram.sh"


def send_telegram_alert(msg: str):
    if TELEGRAM_SCRIPT.exists() and os.access(TELEGRAM_SCRIPT, os.X_OK):
        try:
            subprocess.run([str(TELEGRAM_SCRIPT), msg], check=False, timeout=15)
        except Exception as e:
            logging.error(f"Erro ao enviar alerta via Telegram: {e}")


def format_reset_time(reset_header):
    if not reset_header:
        return "na próxima virada UTC"
    try:
        ts = int(reset_header)
        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        dt_sp = dt.astimezone(zoneinfo.ZoneInfo("America/Sao_Paulo"))
        return dt_sp.strftime("%H:%M:%S BRT (%d/%m/%Y)")
    except Exception:
        return f"timestamp {reset_header}"


def check_cloudflare_list(account_id, list_id, headers):
    try:
        req = urllib.request.Request(
            f"https://api.cloudflare.com/client/v4/accounts/{account_id}/rules/lists/{list_id}",
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("result", {}).get("num_items", 0)
    except Exception as e:
        logging.warning(f"Não foi possível consultar contagem atual do Cloudflare: {e}")
        return None


def main():
    abuse_key = os.environ.get("ABUSEIPDB_API_KEY")
    cf_email = os.environ.get("CLOUDFLARE_EMAIL")
    cf_key = os.environ.get("CLOUDFLARE_API_KEY")
    account_id = os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    list_id = os.environ.get("CLOUDFLARE_LIST_ID")

    confidence = int(os.environ.get("ABUSE_CONFIDENCE_MINIMUM", 90))
    limit = int(os.environ.get("ABUSE_IP_LIMIT", 10000))

    if not all([abuse_key, cf_email, cf_key, account_id, list_id]):
        logging.error("[ERRO] Variáveis obrigatórias ausentes. Configure o arquivo config.env ou variáveis de ambiente:")
        logging.error("ABUSEIPDB_API_KEY, CLOUDFLARE_EMAIL, CLOUDFLARE_API_KEY, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_LIST_ID")
        sys.exit(1)

    cf_headers = {
        "X-Auth-Email": cf_email,
        "X-Auth-Key": cf_key,
        "Content-Type": "application/json"
    }

    logging.info("Iniciando download da lista de reputação AbuseIPDB...")
    req_abuse = urllib.request.Request(
        f"https://api.abuseipdb.com/api/v2/blacklist?confidenceMinimum={confidence}&limit={limit}",
        headers={
            "Key": abuse_key,
            "Accept": "application/json",
            "User-Agent": "AbuseIPDB-Cloudflare-Sync/1.0"
        }
    )

    try:
        with urllib.request.urlopen(req_abuse, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            raw_items = data.get("data", [])
    except urllib.error.HTTPError as e:
        if e.code == 429:
            reset_header = e.headers.get("X-RateLimit-Reset")
            reset_time = format_reset_time(reset_header)
            current_items = check_cloudflare_list(account_id, list_id, cf_headers)
            msg = (
                f"Limite diário da API AbuseIPDB atingido. "
                f"A lista existente no Cloudflare ({current_items or limit} IPs) permanece ativa e protegendo o host. "
                f"O limite será renovado às {reset_time}."
            )
            logging.warning(msg)
            sys.exit(0)
        else:
            err = f"Erro HTTP {e.code} ao baixar lista do AbuseIPDB: {e.reason}"
            logging.error(err)
            send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
            sys.exit(1)
    except Exception as e:
        err = f"Erro inesperado ao baixar lista do AbuseIPDB: {e}"
        logging.error(err)
        send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
        sys.exit(1)

    total_ips = len(raw_items)
    logging.info(f"Total de {total_ips} IPs obtidos do AbuseIPDB com confiança >= {confidence}%.")

    if total_ips == 0:
        err = "A lista retornada pelo AbuseIPDB está vazia. Abortando para preservar os IPs atuais no Cloudflare."
        logging.error(err)
        send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
        sys.exit(1)

    cf_items = [
        {
            "ip": item["ipAddress"],
            "comment": f"AbuseIPDB score {item.get('abuseConfidenceScore', 100)}"
        }
        for item in raw_items
        if "ipAddress" in item
    ]

    logging.info(f"Enviando {len(cf_items)} IPs para a API do Cloudflare (List ID: {list_id})...")
    payload = json.dumps(cf_items).encode("utf-8")
    req_cf = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account_id}/rules/lists/{list_id}/items",
        data=payload,
        headers=cf_headers,
        method="PUT"
    )

    try:
        with urllib.request.urlopen(req_cf, timeout=60) as resp:
            cf_res = json.loads(resp.read().decode("utf-8"))
            op_id = cf_res.get("result", {}).get("operation_id")
    except Exception as e:
        err = f"Erro ao enviar lista para a API do Cloudflare: {e}"
        logging.error(err)
        send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
        sys.exit(1)

    if not op_id:
        err = f"Cloudflare não retornou operation_id: {cf_res}"
        logging.error(err)
        send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
        sys.exit(1)

    logging.info(f"Operação em lote iniciada no Cloudflare. ID: {op_id}. Aguardando conclusão...")

    completed = False
    for attempt in range(30):
        time.sleep(2)
        try:
            req_op = urllib.request.Request(
                f"https://api.cloudflare.com/client/v4/accounts/{account_id}/rules/lists/bulk_operations/{op_id}",
                headers=cf_headers
            )
            with urllib.request.urlopen(req_op, timeout=30) as resp_op:
                op_data = json.loads(resp_op.read().decode("utf-8"))
                status = op_data.get("result", {}).get("status")
                if status == "completed":
                    completed = True
                    break
                elif status in ("failed", "error"):
                    err = f"Operação do Cloudflare falhou com status {status}: {op_data}"
                    logging.error(err)
                    send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
                    sys.exit(1)
        except Exception as e:
            logging.warning(f"Tentativa {attempt + 1}: erro ao checar status: {e}")

    if not completed:
        err = f"Timeout aguardando conclusão da operação {op_id} no Cloudflare."
        logging.error(err)
        send_telegram_alert(f"⚠️ [AbuseIPDB Sync] {err}")
        sys.exit(1)

    logging.info(f"[✔] Sucesso! {len(cf_items)} IPs maliciosos sincronizados no Cloudflare WAF.")


if __name__ == "__main__":
    main()
