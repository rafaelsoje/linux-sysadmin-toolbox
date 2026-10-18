#!/usr/bin/env bash
# ==============================================================================
# Script: chat-telegram.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Envia mensagens e alertas para Telegram via Bot API
#            com suporte a STDIN, HTML, MarkdownV2 e urlencode.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="${SCRIPT_DIR}/../config.env"

if [[ -f "${CONFIG_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_ENV}"
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

if [[ -z "${TOKEN}" || -z "${CHAT_ID}" ]]; then
    echo "[AVISO] TELEGRAM_BOT_TOKEN ou TELEGRAM_CHAT_ID não definidos. Mensagem ignorada." >&2
    exit 0
fi

API_URL="https://api.telegram.org/bot${TOKEN}/sendMessage"

MODE=""
TITLE=""
BODY=""

print_help() {
    cat <<EOF
Uso: $(basename "$0") [--mode HTML|MarkdownV2] [--title TITULO] [--body TEXTO] [MENSAGEM]
EOF
}

escape_markdown_v2() {
    sed -E 's/([_*\[\]\(\)~`>#+\-=|{}\.!\\])/\\\1/g'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="${2:-}"; shift 2 ;;
        --title) TITLE="${2:-}"; shift 2 ;;
        --body) BODY="${2:-}"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *)
            if [[ -z "${BODY}" ]]; then
                BODY="$1"
            else
                BODY="${BODY} $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "${BODY}" ]] && ! [ -t 0 ]; then
    BODY="$(cat)"
fi

if [[ -z "${BODY}" ]]; then
    exit 0
fi

if [[ -n "${TITLE}" ]]; then
    case "$MODE" in
        HTML) MESSAGE="<b>${TITLE}</b>%0A${BODY}" ;;
        MarkdownV2) MESSAGE="*${TITLE//*/\\*}*\n${BODY}" ;;
        *) MESSAGE="${TITLE}\n${BODY}" ;;
    esac
else
    MESSAGE="${BODY}"
fi

PARSE_MODE=""
case "$MODE" in
    HTML) PARSE_MODE="HTML" ;;
    MarkdownV2)
        PARSE_MODE="MarkdownV2"
        MESSAGE="$(printf "%b" "$MESSAGE" | escape_markdown_v2)"
        ;;
    *) ;;
esac

if [[ -n "$PARSE_MODE" ]]; then
    curl -4 -sS --connect-timeout 5 --max-time 15 -X POST "$API_URL" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=${PARSE_MODE}" \
        --data-urlencode "text=$(printf "%b" "$MESSAGE")" >/dev/null || true
else
    curl -4 -sS --connect-timeout 5 --max-time 15 -X POST "$API_URL" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=$(printf "%b" "$MESSAGE")" >/dev/null || true
fi

