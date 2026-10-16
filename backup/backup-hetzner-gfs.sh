#!/usr/bin/env bash
# ==============================================================================
# Script: backup-hetzner-gfs.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Rotina de backup com verificação de integridade SHA-256,
#            sincronização em nuvem via Rclone e retenção histórica GFS
#            (Grandfather-Father-Son: Diário, Semanal, Mensal, Anual).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configurações (podem ser sobrescritas por variáveis de ambiente)
# ------------------------------------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-/backup}"
REMOTE="${REMOTE:-hetzner-backup}"
REMOTE_PATH="${REMOTE_PATH:-backup}"
BACKUP_SOURCES="${BACKUP_SOURCES:-/etc /var/www}"
LOG_FILE="${LOG_FILE:-/var/log/backup.log}"

DATE=$(date +"%Y-%m-%d")
MONTH_YEAR=$(date +"%m-%Y")
BACKUP_NAME="backup-${DATE}.tar.gz"
LOCAL_BACKUP_PATH="${BACKUP_DIR}/${MONTH_YEAR}"
FULL_BACKUP_PATH="${LOCAL_BACKUP_PATH}/${BACKUP_NAME}"
HASH_FILE="${FULL_BACKUP_PATH}.sha256"

# ------------------------------------------------------------------------------
# Funções Utilitárias
# ------------------------------------------------------------------------------
log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] ${message}" | tee -a "${LOG_FILE}"
}

check_dependencies() {
    for cmd in tar sha256sum rclone awk; do
        if ! command -v "${cmd}" &>/dev/null; then
            log "[✘] Dependência ausente: ${cmd}. Por favor, instale-a."
            exit 1
        fi
    done
}

# ------------------------------------------------------------------------------
# Execução Principal do Backup
# ------------------------------------------------------------------------------
check_dependencies

mkdir -p "${LOCAL_BACKUP_PATH}"
touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/tmp/backup.log"

log "[+] Iniciando backup dos diretórios: ${BACKUP_SOURCES}"

# Criação do arquivo tar gzip preservando permissões POSIX
# shellcheck disable=SC2086
tar --create --gzip --preserve-permissions --file="${FULL_BACKUP_PATH}" ${BACKUP_SOURCES}
log "[✔] Compactação concluída: ${FULL_BACKUP_PATH}"

# Geração de hash SHA-256 para auditoria de integridade
sha256sum "${FULL_BACKUP_PATH}" | awk '{print $1}' > "${HASH_FILE}"
LOCAL_HASH=$(cat "${HASH_FILE}")
log "[+] Hash SHA-256 gerado: ${LOCAL_HASH}"

# Upload para o Storage remoto via Rclone
log "[+] Enviando backup e hash para o remote '${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/'..."
rclone copy "${FULL_BACKUP_PATH}" "${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/"
rclone copy "${HASH_FILE}" "${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/"

# Validação remota de integridade
log "[+] Validando integridade remota..."
REMOTE_HASH=$(rclone cat "${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/$(basename "${HASH_FILE}")" 2>/dev/null || true)

if [[ "${REMOTE_HASH}" == "${LOCAL_HASH}" ]]; then
    log "[✔] Integridade confirmada! O hash remoto coincide com o arquivo local."
    # Remove arquivo temporário local para liberar espaço em disco
    rm -f "${FULL_BACKUP_PATH}" "${HASH_FILE}"
    log "[+] Arquivo temporário local removido com sucesso."
else
    log "[✘] Divergência no hash remoto! Tentando retransmitir..."
    rclone copy "${FULL_BACKUP_PATH}" "${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/"
    rclone copy "${HASH_FILE}" "${REMOTE}:${REMOTE_PATH}/${MONTH_YEAR}/"
fi

# ------------------------------------------------------------------------------
# Política de Retenção GFS (Grandfather-Father-Son)
# ------------------------------------------------------------------------------
manage_gfs_retention() {
    log "[+] Aplicando política de retenção GFS..."

    # 1. Backups diários: manter 7 dias
    rclone delete "${REMOTE}:${REMOTE_PATH}/daily/" --min-age 7d 2>/dev/null || true

    # 2. Promoção semanal (aos domingos) e expiração após 30 dias
    if [[ $(date +%u) -eq 7 ]]; then
        rclone move "${REMOTE}:${REMOTE_PATH}/daily/" "${REMOTE}:${REMOTE_PATH}/weekly/" --max-age 7d 2>/dev/null || true
    fi
    rclone delete "${REMOTE}:${REMOTE_PATH}/weekly/" --min-age 30d 2>/dev/null || true

    # 3. Promoção mensal (dia 01) e expiração após 180 dias (6 meses)
    if [[ $(date +%d) == "01" ]]; then
        rclone move "${REMOTE}:${REMOTE_PATH}/weekly/" "${REMOTE}:${REMOTE_PATH}/monthly/" --max-age 30d 2>/dev/null || true
    fi
    rclone delete "${REMOTE}:${REMOTE_PATH}/monthly/" --min-age 180d 2>/dev/null || true

    # 4. Promoção anual (01 de janeiro) e expiração após 730 dias (2 anos)
    if [[ $(date +%m-%d) == "01-01" ]]; then
        rclone move "${REMOTE}:${REMOTE_PATH}/monthly/" "${REMOTE}:${REMOTE_PATH}/yearly/" --max-age 365d 2>/dev/null || true
    fi
    rclone delete "${REMOTE}:${REMOTE_PATH}/yearly/" --min-age 730d 2>/dev/null || true

    log "[✔] Manutenção de retenção GFS finalizada."
}

manage_gfs_retention

log "[✔] Ciclo de backup concluído com sucesso."
exit 0
