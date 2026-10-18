#!/usr/bin/env bash
# ==============================================================================
# Script: arquivos-criticos-fim.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: HIDS - File Integrity Monitoring (FIM) para arquivos e diretórios críticos.
#            Gera baseline de integridade criptográfica e detecta alterações,
#            injeção de web shells, backdoors ou adulterações de configurações.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="${SCRIPT_DIR}/../config.env"

if [[ -f "${CONFIG_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_ENV}"
fi

LOG_DIR="${LOG_DIR:-${HOME}/.hids/logs}"
HASH_ANTIGO="${LOG_DIR}/fim_hashes_antigos.txt"
HASH_ATUAL="${LOG_DIR}/fim_hashes_atuais.txt"
LOG_ALTERACOES="${LOG_DIR}/fim_alteracoes.log"
CHAT_SCRIPT="${SCRIPT_DIR}/chat-telegram.sh"

# Diretórios alvos para monitoramento de integridade
TARGETS="${FIM_TARGETS:-/etc/nginx/ /etc/ssh/}"

# Padrões comuns a ignorar para evitar falsos positivos
IGNORAR=(
    "*/vendor*"
    "*/releases*"
    "*/.git*"
    "*/writable*"
    "*/cache*"
    "*/logs*"
    "*.log"
)

mkdir -p "${LOG_DIR}"

EXCLUDE_EXPR=""
for item in "${IGNORAR[@]}"; do
    EXCLUDE_EXPR+=" -path \"${item}\" -prune -o"
done

# Coleta de hashes SHA-256 dos arquivos monitorados
# shellcheck disable=SC2086
eval "find ${TARGETS} ${EXCLUDE_EXPR} -type f -print0" 2>/dev/null | xargs -0 sha256sum 2>/dev/null | sort -k2 > "${HASH_ATUAL}" || true

if [[ -f "${HASH_ANTIGO}" ]]; then
    DIFF=$(diff -u "${HASH_ANTIGO}" "${HASH_ATUAL}" || true)

    if [[ -n "${DIFF}" ]]; then
        NOVOS=""
        ALTERADOS=""
        REMOVIDOS=""

        # Analisa linhas adicionadas (+) e removidas (-)
        while IFS= read -r line; do
            if [[ "${line}" =~ ^\+([a-f0-9]{64})[[:space:]]+(.*)$ ]]; then
                hash_n="${BASH_REMATCH[1]}"
                file_n="${BASH_REMATCH[2]}"
                # Verifica se o arquivo já existia com outro hash (alterado) ou se é novo
                if grep -qs "[[:space:]]${file_n}\$" "${HASH_ANTIGO}"; then
                    ALTERADOS+=" ✏️ ${file_n}\n"
                else
                    NOVOS+=" 📥 ${file_n}\n"
                fi
            elif [[ "${line}" =~ ^\-([a-f0-9]{64})[[:space:]]+(.*)$ ]]; then
                file_r="${BASH_REMATCH[2]}"
                if ! grep -qs "[[:space:]]${file_r}\$" "${HASH_ATUAL}"; then
                    REMOVIDOS+=" 🗑️ ${file_r}\n"
                fi
            fi
        done <<< "${DIFF}"

        RESUMO=""
        [[ -n "${NOVOS}" ]] && RESUMO+="Arquivos Novos Detectados:\n${NOVOS}\n"
        [[ -n "${ALTERADOS}" ]] && RESUMO+="Arquivos Modificados:\n${ALTERADOS}\n"
        [[ -n "${REMOVIDOS}" ]] && RESUMO+="Arquivos Excluídos:\n${REMOVIDOS}\n"

        if [[ -n "${RESUMO}" ]]; then
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            echo -e "[${TIMESTAMP}]\n${RESUMO}" >> "${LOG_ALTERACOES}"

            MENSAGEM="🚨 [HIDS - FIM Alerta] Integridade Comprometida!\n\n${RESUMO}"
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

