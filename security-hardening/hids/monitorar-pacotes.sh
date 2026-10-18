#!/usr/bin/env bash
# ==============================================================================
# Script: monitorar-pacotes.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: HIDS - Auditoria periódica de pacotes instalados e removidos no SO.
#            Alerta sobre novos binários ou ferramentas injetadas no sistema.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="${SCRIPT_DIR}/../config.env"

if [[ -f "${CONFIG_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_ENV}"
fi

LOG_DIR="${LOG_DIR:-${HOME}/.hids/logs}"
PACOTES_ANTIGO="${LOG_DIR}/pacotes_antigo.txt"
PACOTES_ATUAL="${LOG_DIR}/pacotes_atual.txt"
ARQUIVO_DIFF="${LOG_DIR}/pacotes_diff.txt"
CHAT_SCRIPT="${SCRIPT_DIR}/chat-telegram.sh"
ALERT_EMAIL="${SECURITY_ALERT_EMAIL:-}"

mkdir -p "${LOG_DIR}"

if ! command -v dpkg &>/dev/null; then
    echo "[AVISO] dpkg não disponível neste host." >&2
    exit 0
fi

# Lista pacotes instalados
dpkg --get-selections | grep -v deinstall | awk '{print $1}' | sort > "${PACOTES_ATUAL}"

if [[ -f "${PACOTES_ANTIGO}" ]]; then
    diff -u "${PACOTES_ANTIGO}" "${PACOTES_ATUAL}" > "${ARQUIVO_DIFF}" || true

    if [[ -s "${ARQUIVO_DIFF}" ]]; then
        ADICIONADOS=$(grep '^+[a-zA-Z0-9]' "${ARQUIVO_DIFF}" | sed 's/^+//' || true)
        REMOVIDOS=$(grep '^-[a-zA-Z0-9]' "${ARQUIVO_DIFF}" | sed 's/^-//' || true)

        if [[ -n "${ADICIONADOS}" || -n "${REMOVIDOS}" ]]; then
            MENSAGEM="🚨 [HIDS Alerta] Modificação na lista de pacotes do sistema!\n\n"

            if [[ -n "${ADICIONADOS}" ]]; then
                MENSAGEM+="📥 Pacotes Instalados:\n${ADICIONADOS}\n\n"
            fi

            if [[ -n "${REMOVIDOS}" ]]; then
                MENSAGEM+="🗑️ Pacotes Removidos:\n${REMOVIDOS}\n"
            fi

            if [[ -n "${ALERT_EMAIL}" ]] && command -v mail &>/dev/null; then
                echo -e "${MENSAGEM}" | mail -s "[HIDS Alerta] Mudança na Lista de Pacotes - $(hostname)" "${ALERT_EMAIL}" || true
            fi

            if [[ -x "${CHAT_SCRIPT}" ]]; then
                MENSAGEM_CORTADA=$(echo -e "${MENSAGEM}" | head -c 3800)
                "${CHAT_SCRIPT}" "${MENSAGEM_CORTADA}" || true
            fi

            echo -e "${MENSAGEM}"
        fi
    fi
fi

mv "${PACOTES_ATUAL}" "${PACOTES_ANTIGO}"
exit 0

