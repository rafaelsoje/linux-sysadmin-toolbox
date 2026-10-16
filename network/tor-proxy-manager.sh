#!/usr/bin/env bash
# ==============================================================================
# Script: tor-proxy-manager.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Gerenciador de Proxy SOCKS5 (Tor local: 127.0.0.1:9050).
#            Testa a conectividade com a rede Tor e gera os comandos de export.
# Uso:
#   Para aplicar no shell atual:
#     source tor-proxy-manager.sh on
#     source tor-proxy-manager.sh off
#   Para verificar o status da conexão Tor:
#     ./tor-proxy-manager.sh status
# ==============================================================================

TOR_HOST="127.0.0.1"
TOR_PORT="9050"
CHECK_URL="https://check.torproject.org/"

test_tor_connection() {
    echo "[+] Verificando conexão Tor através de ${TOR_HOST}:${TOR_PORT}..."
    if ! command -v curl &>/dev/null; then
        echo "[ERRO] 'curl' não está instalado." >&2
        return 1
    fi

    HTTP_CODE=$(curl --socks5 "${TOR_HOST}:${TOR_PORT}" --max-time 10 -s -o /dev/null -w "%{http_code}" "${CHECK_URL}" 2>/dev/null || echo "000")

    if [[ "${HTTP_CODE}" == "200" ]]; then
        echo "[✔] Conexão Tor estabelecida com sucesso via SOCKS5!"
        return 0
    else
        echo "[✘] Falha ao conectar ao serviço Tor na porta ${TOR_PORT} (HTTP ${HTTP_CODE})."
        echo "    Verifique se o daemon do Tor está ativo: 'systemctl status tor'"
        return 1
    fi
}

enable_proxy() {
    export socks_proxy="socks5://${TOR_HOST}:${TOR_PORT}"
    export http_proxy="socks5://${TOR_HOST}:${TOR_PORT}"
    export https_proxy="socks5://${TOR_HOST}:${TOR_PORT}"
    export all_proxy="socks5://${TOR_HOST}:${TOR_PORT}"
    echo "[✔] Variáveis de proxy SOCKS5 exportadas para o terminal atual."
    test_tor_connection
}

disable_proxy() {
    unset socks_proxy http_proxy https_proxy all_proxy
    echo "[✔] Variáveis de proxy removidas do terminal atual."
}

ACTION="${1:-status}"

case "${ACTION}" in
    on|start)
        enable_proxy
        ;;
    off|stop)
        disable_proxy
        ;;
    status|check)
        test_tor_connection
        ;;
    *)
        echo "Uso: $0 {on|off|status}"
        echo "Nota: Para alterar variáveis de ambiente da sessão atual, utilize:"
        echo "  source $0 on"
        echo "  source $0 off"
        ;;
esac
