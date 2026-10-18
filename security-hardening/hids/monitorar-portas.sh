#!/usr/bin/env bash
# ==============================================================================
# Script: monitorar-portas.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: HIDS - Monitoramento contínuo de portas TCP/UDP em escuta (LISTEN).
#            Detecta novas portas expostas e alerta se portas essenciais caírem.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-${HOME}/.hids/logs}"
LOG_ANTERIOR="${LOG_DIR}/portas_antigas.txt"
LOG_ATUAL="${LOG_DIR}/portas_atuais.txt"
CHAT_SCRIPT="${SCRIPT_DIR}/chat-telegram.sh"

# Portas de risco que nunca devem abrir sem autorização
PORTAS_CRITICAS_ABRIR=("21" "23" "25" "80" "110" "143" "8080" "10000")
# Portas fundamentais que devem permanecer ativas
PORTAS_ESSENCIAIS_MANTER=("22" "443")

mkdir -p "${LOG_DIR}"

# Lista portas ativas em LISTEN de forma padronizada
ss -tunlp 2>/dev/null | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -n | uniq > "${LOG_ATUAL}" || true

if [[ -f "${LOG_ANTERIOR}" ]]; then
    DIFERENCA=$(diff -u "${LOG_ANTERIOR}" "${LOG_ATUAL}" || true)

    if [[ -n "${DIFERENCA}" ]]; then
        MENSAGEM="🚨 [HIDS Alerta] Alteração detectada nas portas de rede em escuta:\n\n"
        MENSAGEM+=$(echo "${DIFERENCA}" | grep -E '^[+-][0-9]' | sed 's/^+/➕ Porta Aberta: /' | sed 's/^-/➖ Porta Fechada: /')

        # Verificação de portas críticas
        for porta in "${PORTAS_CRITICAS_ABRIR[@]}"; do
            if grep -q "^${porta}\$" "${LOG_ATUAL}" && ! grep -q "^${porta}\$" "${LOG_ANTERIOR}"; then
                MENSAGEM+="\n⚠️ [PERIGO] Porta de alto risco recém-aberta: ${porta}!"
            fi
        done

        # Verificação de portas essenciais
        for porta in "${PORTAS_ESSENCIAIS_MANTER[@]}"; do
            if ! grep -q "^${porta}\$" "${LOG_ATUAL}"; then
                MENSAGEM+="\n🚨 [CRÍTICO] Serviço essencial indisponível na porta: ${porta}!"
            fi
        done

        if [[ -x "${CHAT_SCRIPT}" ]]; then
            "${CHAT_SCRIPT}" "${MENSAGEM}" || true
        fi
        echo -e "${MENSAGEM}"
    fi
else
    if [[ -x "${CHAT_SCRIPT}" ]]; then
        "${CHAT_SCRIPT}" "✅ [HIDS] Monitoramento de portas de rede inicializado." || true
    fi
fi

mv "${LOG_ATUAL}" "${LOG_ANTERIOR}"
exit 0

