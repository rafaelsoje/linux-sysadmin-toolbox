#!/usr/bin/env bash
# ==============================================================================
# Script: userinfo.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Auditoria de usuário Linux (UID, GID, grupos, diretório home,
#            consumo de disco e histórico do último login).
# Uso: ./userinfo.sh <usuario>
# ==============================================================================

set -euo pipefail

TARGET_USER="${1:-}"

if [[ -z "${TARGET_USER}" ]]; then
    echo "Uso: $0 <nome_do_usuario>"
    exit 1
fi

if ! id "${TARGET_USER}" &>/dev/null; then
    echo "[ERRO] Usuário '${TARGET_USER}' não encontrado no sistema." >&2
    exit 1
fi

USER_UID=$(id -u "${TARGET_USER}")
USER_GID=$(id -g "${TARGET_USER}")
USER_GROUPS=$(id -Gn "${TARGET_USER}")
USER_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
USER_SHELL=$(getent passwd "${TARGET_USER}" | cut -d: -f7)

if [[ -d "${USER_HOME}" ]]; then
    HOME_USAGE=$(du -sh "${USER_HOME}" 2>/dev/null | cut -f1 || echo "Sem permissão de leitura")
else
    HOME_USAGE="Diretório home não existe"
fi

echo "=========================================================="
echo " Auditoria do Usuário: ${TARGET_USER}"
echo "=========================================================="
echo " - UID:           ${USER_UID}"
echo " - GID Primário:  ${USER_GID}"
echo " - Grupos:        ${USER_GROUPS}"
echo " - Diretório Home: ${USER_HOME}"
echo " - Shell Padrão:  ${USER_SHELL}"
echo " - Espaço em uso: ${HOME_USAGE}"
echo
echo " Último Login (lastlog):"
lastlog -u "${TARGET_USER}" 2>/dev/null || echo "Utilitário lastlog não disponível."
echo "=========================================================="
exit 0
