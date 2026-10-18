#!/usr/bin/env bash
# ==============================================================================
# Script: setup-hids.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Instalador e inicializador automatizado da suíte HIDS e Hardening.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
EXAMPLE_FILE="${SCRIPT_DIR}/config.example.env"
LOG_DIR="${HOME}/.hids/logs"

echo "================================================================================"
echo " INSTALADOR & INICIALIZADOR HIDS - LINUX SYSADMIN TOOLBOX"
echo "================================================================================"

# 1. Criação do diretório de estado e logs
echo "[+] Criando diretório de logs e baselines em: ${LOG_DIR}..."
mkdir -p "${LOG_DIR}"

# 2. Configuração de ambiente
if [[ ! -f "${CONFIG_FILE}" ]]; then
    if [[ -f "${EXAMPLE_FILE}" ]]; then
        echo "[+] Criando 'config.env' a partir do template de exemplo..."
        cp "${EXAMPLE_FILE}" "${CONFIG_FILE}"
        chmod 600 "${CONFIG_FILE}"
        echo "[!] Arquivo 'config.env' criado. Edite-o com seu TOKEN do Telegram e credenciais."
    fi
else
    echo "[✔] Arquivo 'config.env' já existente."
fi

# 3. Ajuste de permissões
echo "[+] Ajustando permissões de execução nos módulos HIDS..."
chmod +x "${SCRIPT_DIR}/hids/"*.sh
chmod +x "${SCRIPT_DIR}/"*.py

# 4. Inicialização de baselines
echo "[+] Gerando baselines iniciais do sistema..."
"${SCRIPT_DIR}/hids/monitorar-portas.sh"
"${SCRIPT_DIR}/hids/monitorar-pacotes.sh"
"${SCRIPT_DIR}/hids/monitorar-bits-especiais.sh"

echo
echo "================================================================================"
echo "[✔] Suíte HIDS inicializada com sucesso!"
echo "    - Logs e histórico armazenados em: ${LOG_DIR}"
echo "    - Para agendar no cron, adicione as chamadas no 'crontab -e':"
echo "        */30 * * * * ${SCRIPT_DIR}/hids/monitorar-portas.sh"
echo "        0 * * * *    ${SCRIPT_DIR}/hids/monitorar-pacotes.sh"
echo "        0 2 * * *    ${SCRIPT_DIR}/hids/monitorar-bits-especiais.sh"
echo "================================================================================"
exit 0
