#!/usr/bin/env bash
# ==============================================================================
# Script: monitorar-bits-especiais.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: HIDS - Auditoria de binários com bits especiais (SUID / SGID).
#            Alerta imediatamente caso novos binários privilegiados surjam no sistema,
#            sinalizando possíveis vetores de escalada de privilégios ou persistência de rootkit.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-${HOME}/.hids/logs}"
HASH_ANTIGO="${LOG_DIR}/suid_sgid_antigo.txt"
HASH_ATUAL="${LOG_DIR}/suid_sgid_atual.txt"
CHAT_SCRIPT="${SCRIPT_DIR}/chat-telegram.sh"

mkdir -p "${LOG_DIR}"

# Varredura de binários com bits SUID (4000) e SGID (2000)
find / \
    \( -perm -4000 -o -perm -2000 \) \
    -type f \
    -not -path "/proc/*" \
    -not -path "/sys/*" \
    -not -path "/dev/*" \
    -not -path "/var/lib/docker/*" \
    -not -path "/mnt/*" \
    2>/dev/null | sort > "${HASH_ATUAL}" || true

if [[ -f "${HASH_ANTIGO}" ]]; then
    DIFERENCA=$(diff -u "${HASH_ANTIGO}" "${HASH_ATUAL}" || true)

    if [[ -n "${DIFERENCA}" ]]; then
        NOVOS=$(echo "${DIFERENCA}" | grep '^+/' | sed 's/^+//' || true)
        REMOVIDOS=$(echo "${DIFERENCA}" | grep '^-/' | sed 's/^-//' || true)

        if [[ -n "${NOVOS}" || -n "${REMOVIDOS}" ]]; then
            MENSAGEM="🚨 [HIDS Alerta] Mudança em binários com bits especiais SUID/SGID!\n\n"

            if [[ -n "${NOVOS}" ]]; then
                MENSAGEM+="⚠️ Novos binários privilegiados detectados:\n${NOVOS}\n\n"
            fi

            if [[ -n "${REMOVIDOS}" ]]; then
                MENSAGEM+="ℹ️ Binários SUID/SGID removidos:\n${REMOVIDOS}\n"
            fi

            if [[ -x "${CHAT_SCRIPT}" ]]; then
                CORTADO=$(echo -e "${MENSAGEM}" | head -c 3800)
                "${CHAT_SCRIPT}" "${CORTADO}" || true
            fi

            echo -e "${MENSAGEM}"
        fi
    fi
fi

mv "${HASH_ATUAL}" "${HASH_ANTIGO}"
exit 0
