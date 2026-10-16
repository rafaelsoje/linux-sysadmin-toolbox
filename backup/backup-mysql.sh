#!/usr/bin/env bash
# ==============================================================================
# Script: backup-mysql.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Dump de bancos de dados MySQL/MariaDB com compactação gzip,
#            autenticação segura sem credenciais hardcoded e retenção local.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configurações
# ------------------------------------------------------------------------------
# Diretório base para backups
BACKUP_DIR="${BACKUP_DIR:-${HOME}/.backup/mysql}"
MONTH_YEAR=$(date +"%m-%Y")
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_DIR="${BACKUP_DIR}/${MONTH_YEAR}"

# Nome do banco (deixe vazio para fazer backup de todos: --all-databases)
DB_NAME="${MYSQL_DATABASE:-}"

# Autenticação segura:
# Recomenda-se utilizar o arquivo ~/.my.cnf com permissão 600:
# [client]
# user = seu_usuario
# password = sua_senha
DB_USER="${MYSQL_USER:-root}"
DB_HOST="${MYSQL_HOST:-localhost}"
DB_PORT="${MYSQL_PORT:-3306}"

# Dias de retenção local para limpeza automática
RETENTION_DAYS="${RETENTION_DAYS:-14}"

# ------------------------------------------------------------------------------
# Validações e Execução
# ------------------------------------------------------------------------------
mkdir -p "${TARGET_DIR}"

if ! command -v mysqldump &>/dev/null; then
    echo "[ERRO] Utilitário 'mysqldump' não encontrado no PATH." >&2
    exit 1
fi

if [[ -n "${DB_NAME}" ]]; then
    BACKUP_FILE="${TARGET_DIR}/backup_${DB_NAME}_${TIMESTAMP}.sql.gz"
    echo "[+] Iniciando backup da base de dados '${DB_NAME}'..."
    mysqldump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --user="${DB_USER}" \
        --single-transaction \
        --quick \
        "${DB_NAME}" | gzip -9 > "${BACKUP_FILE}"
else
    BACKUP_FILE="${TARGET_DIR}/backup_all_databases_${TIMESTAMP}.sql.gz"
    echo "[+] Iniciando backup de todos os bancos de dados (--all-databases)..."
    mysqldump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --user="${DB_USER}" \
        --single-transaction \
        --quick \
        --all-databases | gzip -9 > "${BACKUP_FILE}"
fi

FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[✔] Backup gerado com sucesso: ${BACKUP_FILE} (${FILE_SIZE})"

# Limpeza automática de dumps locais antigos
if [[ "${RETENTION_DAYS}" -gt 0 ]]; then
    echo "[+] Removendo backups locais com mais de ${RETENTION_DAYS} dias..."
    find "${BACKUP_DIR}" -type f -name "*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete
fi

echo "[✔] Processo finalizado."
exit 0
