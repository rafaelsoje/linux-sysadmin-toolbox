#!/usr/bin/env bash
# ==============================================================================
# Script: backup-postgres.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Dump consistente de bancos de dados PostgreSQL com pg_dump/pg_dumpall,
#            compactação gzip -9 em pipeline, autenticação segura e retenção local.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configurações
# ------------------------------------------------------------------------------
# Diretório base para backups
BACKUP_DIR="${BACKUP_DIR:-${HOME}/.backup/postgres}"
MONTH_YEAR=$(date +"%m-%Y")
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_DIR="${BACKUP_DIR}/${MONTH_YEAR}"

# Nome do banco específico (deixe vazio para fazer backup de todo o cluster via pg_dumpall)
DB_NAME="${PGDATABASE:-}"

# Autenticação segura:
# Recomenda-se utilizar o arquivo ~/.pgpass com permissão 0600:
# hostname:port:database:username:password
DB_USER="${PGUSER:-postgres}"
DB_HOST="${PGHOST:-localhost}"
DB_PORT="${PGPORT:-5432}"

# Dias de retenção local para limpeza automática
RETENTION_DAYS="${RETENTION_DAYS:-14}"

# ------------------------------------------------------------------------------
# Validações e Execução
# ------------------------------------------------------------------------------
mkdir -p "${TARGET_DIR}"

# Validação do arquivo ~/.pgpass caso exista
if [[ -f "${HOME}/.pgpass" ]]; then
    PERMS=$(stat -c "%a" "${HOME}/.pgpass" 2>/dev/null || stat -f "%OLp" "${HOME}/.pgpass" 2>/dev/null || true)
    if [[ "${PERMS}" != "600" && "${PERMS}" != "0600" ]]; then
        echo "[!] Aviso: Permissões de ~/.pgpass estão como '${PERMS}'. Ajustando para 0600..."
        chmod 600 "${HOME}/.pgpass"
    fi
fi

if [[ -n "${DB_NAME}" ]]; then
    if ! command -v pg_dump &>/dev/null; then
        echo "[ERRO] Utilitário 'pg_dump' não encontrado no PATH." >&2
        exit 1
    fi

    BACKUP_FILE="${TARGET_DIR}/backup_${DB_NAME}_${TIMESTAMP}.sql.gz"
    echo "[+] Iniciando backup da base de dados '${DB_NAME}'..."

    pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        "${DB_NAME}" | gzip -9 > "${BACKUP_FILE}"
else
    if ! command -v pg_dumpall &>/dev/null; then
        echo "[ERRO] Utilitário 'pg_dumpall' não encontrado no PATH." >&2
        exit 1
    fi

    BACKUP_FILE="${TARGET_DIR}/backup_all_databases_${TIMESTAMP}.sql.gz"
    echo "[+] Iniciando backup completo de todas as bases de dados (pg_dumpall)..."

    pg_dumpall \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --clean \
        --if-exists | gzip -9 > "${BACKUP_FILE}"
fi

FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[✔] Backup PostgreSQL gerado com sucesso: ${BACKUP_FILE} (${FILE_SIZE})"

# Limpeza automática de dumps locais antigos
if [[ "${RETENTION_DAYS}" -gt 0 ]]; then
    echo "[+] Removendo backups locais com mais de ${RETENTION_DAYS} dias..."
    find "${BACKUP_DIR}" -type f -name "*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete
fi

echo "[✔] Processo finalizado."
exit 0
