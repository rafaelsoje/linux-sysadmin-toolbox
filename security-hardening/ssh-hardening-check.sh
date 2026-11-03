#!/usr/bin/env bash
# ==============================================================================
# Script: ssh-hardening-check.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Auditor de conformidade e hardening para configurações do OpenSSH
#            Server (sshd_config), baseado em CIS Benchmarks e NIST SP 800-128.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Cores e Formatação
# ------------------------------------------------------------------------------
USE_COLOR=true
if [[ ! -t 1 ]] || [[ "${1:-}" == "--no-color" ]] || [[ "${2:-}" == "--no-color" ]]; then
    USE_COLOR=false
fi

if [[ "${USE_COLOR}" == "true" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_WHITE='\033[1;37m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_CYAN=''
    C_WHITE=''
fi

# ------------------------------------------------------------------------------
# Parâmetros e Variáveis de Estado
# ------------------------------------------------------------------------------
CONFIG_FILE="/etc/ssh/sshd_config"
QUIET_MODE=false
TOTAL_SCORE=0
MAX_SCORE=100
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
RECOMMENDATIONS=()

# ------------------------------------------------------------------------------
# Ajuda e Uso
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Uso: $(basename "$0") [OPÇÕES]

Auditor defensivo de configurações do servidor OpenSSH (sshd_config).

OPÇÕES:
  -c, --config <ARQUIVO>   Caminho para o arquivo sshd_config (padrão: /etc/ssh/sshd_config)
  --no-color               Desativa saída com cores ANSI
  -q, --quiet              Modo silencioso (exibe apenas sumário e alertas críticos)
  -h, --help               Exibe este menu de ajuda e encerra

EXEMPLOS:
  $(basename "$0")
  $(basename "$0") -c /etc/ssh/sshd_config
  $(basename "$0") -c /backup/sshd_config --no-color
EOF
    exit 0
}

# Tratamento de argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Opção inválida: $1" >&2
            show_help
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Resolução de Diretivas SSH
# ------------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo -e "${C_RED}[ERRO] Arquivo de configuração não encontrado: ${CONFIG_FILE}${C_RESET}" >&2
    exit 1
fi

# Tenta obter configurações resolvidas com sshd -T (se suportado e permitido)
SSHD_RESOLVED_CONFIG=""
if command -v sshd >/dev/null 2>&1; then
    if sshd -T -f "${CONFIG_FILE}" 2>/dev/null >/dev/null; then
        SSHD_RESOLVED_CONFIG=$(sshd -T -f "${CONFIG_FILE}" 2>/dev/null || true)
    fi
fi

# Função auxiliar para extrair o valor da diretiva
get_directive() {
    local key="$1"
    local default_val="$2"
    local lower_key
    lower_key=$(echo "${key}" | tr '[:upper:]' '[:lower:]')

    # 1. Se sshd -T funcionou, busca nele (formato: chave minúscula + espaço + valor)
    if [[ -n "${SSHD_RESOLVED_CONFIG}" ]]; then
        local found
        found=$(echo "${SSHD_RESOLVED_CONFIG}" | awk -v k="^${lower_key} " '$0 ~ k {print substr($0, length(k)+1); exit}')
        if [[ -n "${found}" ]]; then
            echo "${found}"
            return 0
        fi
    fi

    # 2. Busca manual no arquivo principal e em includes (*.conf)
    local val=""
    val=$(grep -i -E "^[[:space:]]*${key}[[:space:]]+" "${CONFIG_FILE}" 2>/dev/null | awk '{print $2}' | head -n 1 || true)

    if [[ -z "${val}" ]]; then
        # Verificar arquivos em Include se houver
        local include_pattern
        include_pattern=$(grep -i -E "^[[:space:]]*Include[[:space:]]+" "${CONFIG_FILE}" 2>/dev/null | awk '{print $2}' | head -n 1 || true)
        if [[ -n "${include_pattern}" ]]; then
            # Se for caminho relativo, baseia-se em /etc/ssh
            if [[ "${include_pattern}" != /* ]]; then
                include_pattern="/etc/ssh/${include_pattern}"
            fi
            # shellcheck disable=SC2086
            val=$(grep -i -h -E "^[[:space:]]*${key}[[:space:]]+" ${include_pattern} 2>/dev/null | awk '{print $2}' | head -n 1 || true)
        fi
    fi

    if [[ -n "${val}" ]]; then
        echo "${val}"
    else
        echo "${default_val}"
    fi
}

# ------------------------------------------------------------------------------
# Helpers de Relatório
# ------------------------------------------------------------------------------
print_result() {
    local status="$1"
    local check_name="$2"
    local details="$3"

    if [[ "${QUIET_MODE}" == "true" && "${status}" == "PASS" ]]; then
        return 0
    fi

    case "${status}" in
        "PASS")
            echo -e "  [${C_GREEN}PASS${C_RESET}] ${C_BOLD}${check_name}${C_RESET}: ${details}"
            ;;
        "WARN")
            echo -e "  [${C_YELLOW}WARN${C_RESET}] ${C_BOLD}${check_name}${C_RESET}: ${details}"
            ;;
        "FAIL")
            echo -e "  [${C_RED}FAIL${C_RESET}] ${C_BOLD}${check_name}${C_RESET}: ${details}"
            ;;
        "INFO")
            echo -e "  [${C_CYAN}INFO${C_RESET}] ${C_BOLD}${check_name}${C_RESET}: ${details}"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Início da Auditoria
# ------------------------------------------------------------------------------
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo -e "${C_BLUE}================================================================================${C_RESET}"
    echo -e "${C_BOLD} AUDITORIA DE HARDENING DO OPENSSH SERVER (sshd_config)${C_RESET}"
    echo -e " Alvo auditado: ${C_WHITE}${CONFIG_FILE}${C_RESET}"
    echo -e " Data da análise: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    if [[ -n "${SSHD_RESOLVED_CONFIG}" ]]; then
        echo -e " Modo de inspeção: ${C_GREEN}Engine ativa do OpenSSH (sshd -T)${C_RESET}"
    else
        echo -e " Modo de inspeção: ${C_YELLOW}Parsing direto de arquivos e Include${C_RESET}"
    fi
    echo -e "${C_BLUE}================================================================================${C_RESET}"
    echo
fi

# 1. PermitRootLogin (Peso: 15)
ROOT_LOGIN=$(get_directive "PermitRootLogin" "prohibit-password")
case "${ROOT_LOGIN,,}" in
    "no")
        TOTAL_SCORE=$((TOTAL_SCORE + 15))
        PASS_COUNT=$((PASS_COUNT + 1))
        print_result "PASS" "PermitRootLogin" "Desativado ('no'). Acesso administrativo requer usuário autenticado com sudo/su."
        ;;
    "prohibit-password"|"without-password")
        TOTAL_SCORE=$((TOTAL_SCORE + 8))
        WARN_COUNT=$((WARN_COUNT + 1))
        print_result "WARN" "PermitRootLogin" "Configurado como '${ROOT_LOGIN}'. Root aceita apenas chaves. Recomendação CIS: definir 'no'."
        RECOMMENDATIONS+=("Desative completamente o login de root alterando 'PermitRootLogin no'.")
        ;;
    "yes")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        print_result "FAIL" "PermitRootLogin" "Permitido com senha ('yes'). Risco crítico de invasão direta por força bruta."
        RECOMMENDATIONS+=("CRÍTICO: Altere urgentemente 'PermitRootLogin no' no sshd_config.")
        ;;
    *)
        WARN_COUNT=$((WARN_COUNT + 1))
        print_result "WARN" "PermitRootLogin" "Valor detectado: '${ROOT_LOGIN}'. Recomendado: 'no'."
        RECOMMENDATIONS+=("Revise a diretiva 'PermitRootLogin' e garanta o valor 'no'.")
        ;;
esac

# 2. PasswordAuthentication (Peso: 15)
PASS_AUTH=$(get_directive "PasswordAuthentication" "yes")
case "${PASS_AUTH,,}" in
    "no")
        TOTAL_SCORE=$((TOTAL_SCORE + 15))
        PASS_COUNT=$((PASS_COUNT + 1))
        print_result "PASS" "PasswordAuthentication" "Desativada ('no'). Autenticação permitida apenas por chaves assimétricas."
        ;;
    *)
        FAIL_COUNT=$((FAIL_COUNT + 1))
        print_result "FAIL" "PasswordAuthentication" "Ativada ('${PASS_AUTH}'). Vulnerável a ataques de força bruta e credenciais vazadas."
        RECOMMENDATIONS+=("Desative a autenticação baseada em senhas: 'PasswordAuthentication no'.")
        ;;
esac

# 3. PermitEmptyPasswords (Peso: 10)
EMPTY_PASS=$(get_directive "PermitEmptyPasswords" "no")
case "${EMPTY_PASS,,}" in
    "no")
        TOTAL_SCORE=$((TOTAL_SCORE + 10))
        PASS_COUNT=$((PASS_COUNT + 1))
        print_result "PASS" "PermitEmptyPasswords" "Bloqueado ('no'). Contas sem senha não conseguem autenticar via SSH."
        ;;
    *)
        FAIL_COUNT=$((FAIL_COUNT + 1))
        print_result "FAIL" "PermitEmptyPasswords" "Permitido ('${EMPTY_PASS}'). Brecha crítica de segurança!"
        RECOMMENDATIONS+=("CRÍTICO: Defina explicitamente 'PermitEmptyPasswords no'.")
        ;;
esac

# 4. PubkeyAuthentication (Peso: 10)
PUBKEY_AUTH=$(get_directive "PubkeyAuthentication" "yes")
case "${PUBKEY_AUTH,,}" in
    "yes")
        TOTAL_SCORE=$((TOTAL_SCORE + 10))
        PASS_COUNT=$((PASS_COUNT + 1))
        print_result "PASS" "PubkeyAuthentication" "Habilitada ('yes'). Permite login via chaves seguras (Ed25519 / RSA 4096)."
        ;;
    *)
        WARN_COUNT=$((WARN_COUNT + 1))
        print_result "WARN" "PubkeyAuthentication" "Desativada ('${PUBKEY_AUTH}'). Dificulta autenticação sem senha."
        RECOMMENDATIONS+=("Habilite autenticação por chaves públicas: 'PubkeyAuthentication yes'.")
        ;;
esac

# 5. MaxAuthTries (Peso: 10)
MAX_TRIES=$(get_directive "MaxAuthTries" "6")
if [[ "${MAX_TRIES}" =~ ^[0-9]+$ ]] && [[ "${MAX_TRIES}" -le 4 ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 10))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "MaxAuthTries" "Limitado rigorosamente a ${MAX_TRIES} tentativas por conexão."
elif [[ "${MAX_TRIES}" =~ ^[0-9]+$ ]] && [[ "${MAX_TRIES}" -le 6 ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
    WARN_COUNT=$((WARN_COUNT + 1))
    print_result "WARN" "MaxAuthTries" "Definido como ${MAX_TRIES} (padrão). Recomendação de hardening: 3 ou 4."
    RECOMMENDATIONS+=("Limite as tentativas de autenticação: adicione 'MaxAuthTries 3'.")
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_result "FAIL" "MaxAuthTries" "Configurado excessivamente como ${MAX_TRIES}. Facilita ataques de dicionário."
    RECOMMENDATIONS+=("Reduza o valor de 'MaxAuthTries' para no máximo 3 ou 4.")
fi

# 6. X11Forwarding (Peso: 10)
X11_FWD=$(get_directive "X11Forwarding" "no")
case "${X11_FWD,,}" in
    "no")
        TOTAL_SCORE=$((TOTAL_SCORE + 10))
        PASS_COUNT=$((PASS_COUNT + 1))
        print_result "PASS" "X11Forwarding" "Desativado ('no'). Elimina risco de sequestro de janelas X11 em servidores headless."
        ;;
    *)
        WARN_COUNT=$((WARN_COUNT + 1))
        print_result "WARN" "X11Forwarding" "Ativado ('${X11_FWD}'). Se este for um servidor sem interface gráfica, deve ser desativado."
        RECOMMENDATIONS+=("Em servidores de produção, desative o repasse X11: 'X11Forwarding no'.")
        ;;
esac

# 7. Idle Timeout: ClientAliveInterval & ClientAliveCountMax (Peso: 10)
ALIVE_INT=$(get_directive "ClientAliveInterval" "0")
ALIVE_MAX=$(get_directive "ClientAliveCountMax" "3")
if [[ "${ALIVE_INT}" =~ ^[0-9]+$ ]] && [[ "${ALIVE_INT}" -gt 0 ]] && [[ "${ALIVE_INT}" -le 900 ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 10))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "Idle Timeout" "Configurado: ${ALIVE_INT}s com tolerância de ${ALIVE_MAX} verificações."
else
    WARN_COUNT=$((WARN_COUNT + 1))
    print_result "WARN" "Idle Timeout" "Inativo ('ClientAliveInterval ${ALIVE_INT}'). Sessões zumbis permanecem abertas indefinidamente."
    RECOMMENDATIONS+=("Configure encerramento por inatividade: 'ClientAliveInterval 300' e 'ClientAliveCountMax 2'.")
fi

# 8. HostbasedAuthentication & IgnoreRhosts (Peso: 5)
HOST_AUTH=$(get_directive "HostbasedAuthentication" "no")
IGNORE_RHOSTS=$(get_directive "IgnoreRhosts" "yes")
if [[ "${HOST_AUTH,,}" == "no" ]] && [[ "${IGNORE_RHOSTS,,}" == "yes" ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "Hostbased & Rhosts" "Autenticação legada e insegura por rhosts/hosts.equiv bloqueada."
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_result "FAIL" "Hostbased & Rhosts" "Configuração insegura detectada (HostbasedAuthentication: ${HOST_AUTH}, IgnoreRhosts: ${IGNORE_RHOSTS})."
    RECOMMENDATIONS+=("Bloqueie autenticação legada: 'HostbasedAuthentication no' e 'IgnoreRhosts yes'.")
fi

# 9. AllowAgentForwarding & AllowTcpForwarding (Peso: 5)
AGENT_FWD=$(get_directive "AllowAgentForwarding" "yes")
TCP_FWD=$(get_directive "AllowTcpForwarding" "yes")
if [[ "${AGENT_FWD,,}" == "no" ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "AllowAgentForwarding" "Desativado ('no'). Protege sockets ssh-agent locais contra hosts remotos comprometidos."
else
    TOTAL_SCORE=$((TOTAL_SCORE + 2))
    WARN_COUNT=$((WARN_COUNT + 1))
    print_result "WARN" "AllowAgentForwarding" "Ativado ('yes'). Recomendado desativar ('no') se não for estritamente indispensável."
    RECOMMENDATIONS+=("Desative o repasse de agent se desnecessário: 'AllowAgentForwarding no'.")
fi

# 10. Porta e Exposição (Peso: 5)
PORT_VAL=$(get_directive "Port" "22")
if [[ "${PORT_VAL}" != "22" ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "Porta SSH" "Customizada na porta ${PORT_VAL} (mitiga ruído de scanners automatizados na Internet)."
else
    TOTAL_SCORE=$((TOTAL_SCORE + 3))
    print_result "INFO" "Porta SSH" "Porta padrão 22 em uso. Recomenda-se uso de Fail2ban e filtragem de firewall perimetral."
fi

# 11. Cifras e Algoritmos Obsoletos (Peso: 5)
CIPHERS_RAW=$(get_directive "Ciphers" "")
MACS_RAW=$(get_directive "MACs" "")
KEX_RAW=$(get_directive "KexAlgorithms" "")
COMBINED_CRYPTO="${CIPHERS_RAW} ${MACS_RAW} ${KEX_RAW}"

OBSOLETE_FOUND=()
for algo in "3des-cbc" "arcfour" "blowfish" "diffie-hellman-group1-sha1" "hmac-md5" "hmac-md5-96"; do
    if echo "${COMBINED_CRYPTO}" | grep -qi "${algo}"; then
        OBSOLETE_FOUND+=("${algo}")
    fi
done

if [[ ${#OBSOLETE_FOUND[@]} -eq 0 ]]; then
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
    PASS_COUNT=$((PASS_COUNT + 1))
    print_result "PASS" "Algoritmos Criptográficos" "Nenhum algoritmo obsoleto conhecido (3DES, Arcfour, MD5, DH-Group1) detectado."
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    print_result "FAIL" "Algoritmos Criptográficos" "Algoritmos inseguros encontrados: ${OBSOLETE_FOUND[*]}"
    RECOMMENDATIONS+=("Remova algoritmos criptográficos obsoletos das diretivas Ciphers, MACs ou KexAlgorithms.")
fi

# ------------------------------------------------------------------------------
# Cálculo da Nota Conceitual
# ------------------------------------------------------------------------------
GRADE="F"
GRADE_COLOR="${C_RED}"
if [[ ${TOTAL_SCORE} -ge 90 ]]; then
    GRADE="A+"
    GRADE_COLOR="${C_GREEN}"
elif [[ ${TOTAL_SCORE} -ge 80 ]]; then
    GRADE="A"
    GRADE_COLOR="${C_GREEN}"
elif [[ ${TOTAL_SCORE} -ge 70 ]]; then
    GRADE="B"
    GRADE_COLOR="${C_CYAN}"
elif [[ ${TOTAL_SCORE} -ge 55 ]]; then
    GRADE="C"
    GRADE_COLOR="${C_YELLOW}"
elif [[ ${TOTAL_SCORE} -ge 40 ]]; then
    GRADE="D"
    GRADE_COLOR="${C_YELLOW}"
fi

# ------------------------------------------------------------------------------
# Sumário Consolidado
# ------------------------------------------------------------------------------
echo
echo -e "${C_BLUE}--------------------------------------------------------------------------------${C_RESET}"
echo -e " RESULTADO DA AUDITORIA:"
echo -e " Pontuação: ${C_BOLD}${TOTAL_SCORE}/${MAX_SCORE}${C_RESET} | Nota de Conformidade: ${GRADE_COLOR}${C_BOLD}${GRADE}${C_RESET}"
echo -e " Verificações: ${C_GREEN}${PASS_COUNT} OK${C_RESET} | ${C_YELLOW}${WARN_COUNT} Alertas${C_RESET} | ${C_RED}${FAIL_COUNT} Falhas${C_RESET}"
echo -e "${C_BLUE}--------------------------------------------------------------------------------${C_RESET}"

if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
    echo
    echo -e "${C_WHITE}${C_BOLD}[*] Ações Recomendadas para Elevação de Hardening:${C_RESET}"
    for i in "${!RECOMMENDATIONS[@]}"; do
        echo -e "  $((i+1)). ${RECOMMENDATIONS[$i]}"
    done
fi

echo -e "${C_BLUE}================================================================================${C_RESET}"

# Exit code: 0 se nota >= 70 e 0 falhas críticas, senão 1
if [[ ${FAIL_COUNT} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
