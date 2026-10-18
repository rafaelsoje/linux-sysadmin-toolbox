#!/usr/bin/env bash
# ==============================================================================
# Script: docker-cleanup.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Manutenção preventiva e liberação de espaço em disco no Docker:
#            - Expura containers parados, redes órfãs e imagens sem uso
#            - Limpa cache de compilação (BuildKit cache)
#            - Trunca arquivos de log excessivos (*-json.log) sem derrubar containers
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configurações Padrão
# ------------------------------------------------------------------------------
MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-50}"
DRY_RUN=false
TRUNCATE_LOGS=true
PRUNE_VOLUMES=false

# ------------------------------------------------------------------------------
# Verificação de Pré-requisitos
# ------------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo "[ERRO] Docker não está instalado ou não foi encontrado no PATH." >&2
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "[ERRO] Não foi possível comunicar com o Docker daemon. Execute como root ou verifique se o serviço está ativo." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Parse de Argumentos
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --with-volumes)
            PRUNE_VOLUMES=true
            shift
            ;;
        --no-logs)
            TRUNCATE_LOGS=false
            shift
            ;;
        -h|--help)
            echo "Uso: $0 [opções]"
            echo "Opções:"
            echo "  --dry-run       Apenas exibe o espaço ocupado sem remover nada"
            echo "  --with-volumes  Remove volumes anônimos não utilizados (cuidado)"
            echo "  --no-logs       Não trunca os arquivos de log de containers"
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1"
            exit 1
            ;;
    esac
done

echo "================================================================================"
echo " MANUTENÇÃO & HIGIENIZAÇÃO DO DOCKER"
echo " Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"

echo "[+] Diagnóstico inicial de armazenamento do Docker:"
docker system df
echo

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[i] Modo --dry-run ativo. Nenhuma alteração foi realizada."
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. Truncamento Seguro de Logs de Containers
# ------------------------------------------------------------------------------
if [[ "${TRUNCATE_LOGS}" == "true" ]]; then
    echo "[+] Verificando logs de containers maiores que ${MAX_LOG_SIZE_MB} MB..."
    LOG_FILES=$(find /var/lib/docker/containers/ -name "*-json.log" -size +"${MAX_LOG_SIZE_MB}"M 2>/dev/null || true)

    if [[ -n "${LOG_FILES}" ]]; then
        for log in ${LOG_FILES}; do
            SIZE=$(du -h "${log}" | cut -f1)
            echo "  [-] Truncando log: ${log} (${SIZE})"
            truncate -s 0 "${log}" 2>/dev/null || true
        done
        echo "[✔] Logs truncados com sucesso (sem interrupção dos containers)."
    else
        echo "  [i] Nenhum log excedeu o limite de ${MAX_LOG_SIZE_MB} MB."
    fi
    echo
fi

# ------------------------------------------------------------------------------
# 2. Limpeza de Recursos Órfãos do Docker
# ------------------------------------------------------------------------------
echo "[+] Removendo containers finalizados e redes não utilizadas..."
docker container prune -f
docker network prune -f

echo "[+] Removendo imagens órfãs (dangling) e cache de compilação..."
docker image prune -f
docker builder prune -f 2>/dev/null || true

if [[ "${PRUNE_VOLUMES}" == "true" ]]; then
    echo "[!] Removendo volumes não utilizados..."
    docker volume prune -f
fi

echo
echo "================================================================================"
echo "[✔] Manutenção finalizada! Novo diagnóstico de armazenamento:"
docker system df
echo "================================================================================"
exit 0
