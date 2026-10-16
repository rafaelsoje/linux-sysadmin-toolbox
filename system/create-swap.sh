#!/usr/bin/env bash
# ==============================================================================
# Script: create-swap.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Criação e ativação automatizada de Swap File no Linux,
#            com verificação de fstab, permissões restritas (0600) e fallback para dd.
# ==============================================================================

set -euo pipefail

SWAP_SIZE="${1:-2G}"
SWAP_FILE="${2:-/swapfile}"

# Verificar privilégios de root
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERRO] Este script deve ser executado como root (sudo)." >&2
    exit 1
fi

echo "=========================================================="
echo " Configuração Automatizada de Swap Linux"
echo " Arquivo de destino: ${SWAP_FILE} | Tamanho: ${SWAP_SIZE}"
echo "=========================================================="

# 1. Verifica se já existe swap ativo
echo "[+] Estado atual da memória Swap:"
swapon --show || true

if [[ -f "${SWAP_FILE}" ]]; then
    echo "[AVISO] O arquivo '${SWAP_FILE}' já existe. Abortando para evitar sobrescrita acidental." >&2
    exit 1
fi

# 2. Alocar espaço para o arquivo swap
echo "[+] Alocando espaço com fallocate..."
if ! fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" 2>/dev/null; then
    echo "[AVISO] fallocate falhou ou não é suportado pelo filesystem. Usando 'dd' como fallback..."
    # Converte 2G ou 4G para megabytes para o dd
    SIZE_NUM=$(echo "${SWAP_SIZE}" | sed 's/[^0-9]//g')
    SIZE_UNIT=$(echo "${SWAP_SIZE}" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')
    
    if [[ "${SIZE_UNIT}" == "G" ]]; then
        COUNT=$(( SIZE_NUM * 1024 ))
    else
        COUNT=${SIZE_NUM}
    fi
    dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${COUNT}" status=progress
fi

# 3. Aplicar permissões de segurança estritas (apenas root)
echo "[+] Ajustando permissões para 0600..."
chmod 600 "${SWAP_FILE}"

# 4. Formatar como Swap
echo "[+] Formatando arquivo como área de swap..."
mkswap "${SWAP_FILE}"

# 5. Ativar swap
echo "[+] Ativando a swap..."
swapon "${SWAP_FILE}"

# 6. Persistir no /etc/fstab se ainda não estiver configurado
if ! grep -qs "${SWAP_FILE}" /etc/fstab; then
    echo "[+] Adicionando entrada permanente no /etc/fstab..."
    echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
    echo "[✔] Entrada gravada em /etc/fstab com sucesso."
else
    echo "[i] Entrada já existente em /etc/fstab."
fi

# 7. Relatório final
echo "=========================================================="
echo "[✔] Swap configurada com sucesso!"
swapon --show
free -h
echo "=========================================================="
exit 0
