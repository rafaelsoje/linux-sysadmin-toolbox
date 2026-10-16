#!/usr/bin/env bash
# ==============================================================================
# Script: sysinfo.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Diagnóstico e inventário técnico do host Linux (Kernel, CPU,
#            Memória, Filesystems, Uptime e Rede).
# ==============================================================================

set -euo pipefail

HOSTNAME=$(hostname)
KERNEL=$(uname -r)
ARCH=$(uname -m)
UPTIME=$(uptime -p 2>/dev/null || uptime)
LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg)

CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo || echo "N/A")
CPU_CORES=$(grep -c "^processor" /proc/cpuinfo || echo "1")

MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
MEM_FREE=$(free -h | awk '/^Mem:/ {print $4}')
SWAP_TOTAL=$(free -h | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free -h | awk '/^Swap:/ {print $3}')

echo "================================================================================"
echo " RELATÓRIO DO SISTEMA: ${HOSTNAME}"
echo " Data/Hora: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "================================================================================"
echo " Sistema Operacional & Kernel:"
echo "   - Kernel:   ${KERNEL} (${ARCH})"
echo "   - Uptime:   ${UPTIME}"
echo "   - Load Avg: ${LOAD_AVG}"
echo
echo " Processador (CPU):"
echo "   - Modelo:   ${CPU_MODEL}"
echo "   - Núcleos:  ${CPU_CORES} core(s)"
echo
echo " Memória RAM & Swap:"
echo "   - Memória:  Total: ${MEM_TOTAL} | Em Uso: ${MEM_USED} | Livre: ${MEM_FREE}"
echo "   - Swap:     Total: ${SWAP_TOTAL} | Em Uso: ${SWAP_USED}"
echo
echo " Partições e Armazenamento (Filesystems):"
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || df -h
echo
echo " Interfaces de Rede Ativas:"
ip -br addr show 2>/dev/null || ifconfig 2>/dev/null || echo "Utilitário 'ip' ou 'ifconfig' não disponível."
echo "================================================================================"
exit 0
