#!/usr/bin/env bash
# ==============================================================================
# Script: rclone-dedupe.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Localiza e remove arquivos duplicados em remotes do Rclone
#            (Google Drive, Google Photos, Hetzner, Nextcloud, S3, etc.).
# ==============================================================================

set -euo pipefail

REMOTE="${1:-}"
DEDUPE_MODE="${2:-oldest}" # Opções do rclone: interactive, skip, first, newest, oldest, rename

if [[ -z "${REMOTE}" ]]; then
    echo "Uso: $0 <remote:caminho> [modo_dedupe]"
    echo "Exemplo: $0 drive:Documentos oldest"
    echo "Opções de modo: oldest (padrão), newest, first, largest, rename, skip"
    exit 1
fi

if ! command -v rclone &>/dev/null; then
    echo "[ERRO] Rclone não encontrado no PATH." >&2
    exit 1
fi

echo "[+] Analisando duplicatas no remote: '${REMOTE}' (Modo: ${DEDUPE_MODE})..."
rclone dedupe "${DEDUPE_MODE}" "${REMOTE}"

echo "[✔] Limpeza de duplicatas concluída para '${REMOTE}'."
exit 0
