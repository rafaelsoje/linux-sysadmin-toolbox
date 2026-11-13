#!/usr/bin/env bash
# ==============================================================================
# Script: kernel-sysctl-check.sh
# Autor: Rafael Soje (https://github.com/rafaelsoje)
# Descrição: Auditor defensivo de parâmetros do kernel Linux (/proc/sys/),
#            baseado em benchmarks do CIS (Center for Internet Security),
#            NIST SP 800-128 e diretrizes de conformidade do CISOfy Lynis.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Cores e Formatação ANSI
# ------------------------------------------------------------------------------
USE_COLOR=true
for arg in "$@"; do
    if [[ "${arg}" == "--no-color" ]]; then
        USE_COLOR=false
        break
    fi
done

if [[ ! -t 1 ]]; then
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
# Variáveis de Estado e Contadores
# ------------------------------------------------------------------------------
QUIET_MODE=false
GENERATE_CONF=false
CONF_OUTPUT=""
APPLY_CHANGES=false

TOTAL_CHECKS=0
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
TOTAL_SCORE=0
MAX_SCORE=100

RECOMMENDATIONS=()

# ------------------------------------------------------------------------------
# Ajuda e Uso
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Uso: $(basename "$0") [OPÇÕES]

Auditor defensivo de parâmetros do kernel Linux (sysctl), baseado em CIS Benchmarks e Lynis.

OPÇÕES:
  -g, --generate-conf [PATH]  Gera arquivo de configuração '99-sysctl-hardening.conf'
  -a, --apply                 Aplica parâmetros recomendados em tempo de execução (requer root)
  -q, --quiet                 Modo silencioso (exibe apenas sumário e avisos/falhas)
      --no-color              Desativa formatação com cores ANSI
  -h, --help                  Exibe este menu de ajuda e encerra

EXEMPLOS:
  $(basename "$0")
  $(basename "$0") --generate-conf /etc/sysctl.d/99-sysctl-hardening.conf
  sudo $(basename "$0") --apply
EOF
    exit 0
}

# Tratamento de argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -g|--generate-conf)
            GENERATE_CONF=true
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                CONF_OUTPUT="$2"
                shift 2
            else
                CONF_OUTPUT="99-sysctl-hardening.conf"
                shift
            fi
            ;;
        -a|--apply)
            APPLY_CHANGES=true
            shift
            ;;
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            show_help
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Leitura e Verificação de Parâmetros
# ------------------------------------------------------------------------------
get_sysctl_value() {
    local key="$1"
    local val=""

    # 1. Tenta leitura direta pelo utilitário sysctl
    if command -v sysctl >/dev/null 2>&1; then
        val=$(sysctl -n "${key}" 2>/dev/null || true)
    fi

    # 2. Fallback para /proc/sys se sysctl não retornar
    if [[ -z "${val}" ]]; then
        local proc_path="/proc/sys/${key//.//}"
        if [[ -r "${proc_path}" ]]; then
            val=$(cat "${proc_path}" 2>/dev/null || true)
        fi
    fi

    echo "${val}"
}

print_result() {
    local status="$1"
    local param="$2"
    local current_val="$3"
    local expected_val="$4"
    local description="$5"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [[ "${QUIET_MODE}" == "true" && "${status}" == "PASS" ]]; then
        return 0
    fi

    case "${status}" in
        "PASS")
            echo -e "  [${C_GREEN}PASS${C_RESET}] ${C_BOLD}${param}${C_RESET} = ${current_val}"
            echo -e "         ${description}"
            ;;
        "WARN")
            echo -e "  [${C_YELLOW}WARN${C_RESET}] ${C_BOLD}${param}${C_RESET} = ${current_val:-<indefinido>} (Recomendado: ${expected_val})"
            echo -e "         ${description}"
            ;;
        "FAIL")
            echo -e "  [${C_RED}FAIL${C_RESET}] ${C_BOLD}${param}${C_RESET} = ${current_val:-<indefinido>} (Recomendado: ${expected_val})"
            echo -e "         ${description}"
            ;;
    esac
}

audit_param() {
    local param="$1"
    local expected="$2"
    local weight="$3"
    local description="$4"
    local remediation="$5"

    local current
    current=$(get_sysctl_value "${param}")

    if [[ -z "${current}" ]]; then
        # Parâmetro não suportado pelo kernel instalado (ex: ipv6 desativado)
        print_result "WARN" "${param}" "não suportado" "${expected}" "${description}"
        WARN_COUNT=$((WARN_COUNT + 1))
        TOTAL_SCORE=$((TOTAL_SCORE + (weight / 2)))
        return 0
    fi

    if [[ "${current}" == "${expected}" ]]; then
        print_result "PASS" "${param}" "${current}" "${expected}" "${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
        TOTAL_SCORE=$((TOTAL_SCORE + weight))
    else
        # Se for um parâmetro de segurança crítico
        if [[ "${weight}" -ge 5 ]]; then
            print_result "FAIL" "${param}" "${current}" "${expected}" "${description}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            print_result "WARN" "${param}" "${current}" "${expected}" "${description}"
            WARN_COUNT=$((WARN_COUNT + 1))
            TOTAL_SCORE=$((TOTAL_SCORE + 1))
        fi
        RECOMMENDATIONS+=("${param} = ${expected} (${remediation})")
    fi
}

# ------------------------------------------------------------------------------
# Execução da Auditoria
# ------------------------------------------------------------------------------
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo -e "${C_BLUE}================================================================================${C_RESET}"
    echo -e "${C_BOLD} AUDITORIA DE SEGURANÇA E HARDENING DO KERNEL LINUX (sysctl)${C_RESET}"
    echo -e " Sistema Operacional: $(uname -s) $(uname -r) ($(uname -m))"
    echo -e " Data da análise:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e " Referências:         CIS Linux Benchmark & NIST SP 800-128"
    echo -e "${C_BLUE}================================================================================${C_RESET}"
    echo
fi

# 1. Defesa de Rede IPv4 (Prevenção de Spoofing, DoS e Roteamento Indevido)
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo -e "${C_CYAN}[1/4] Defesa de Rede IPv4 (Anti-Spoofing & Mitigação DoS):${C_RESET}"
fi

audit_param "net.ipv4.conf.all.rp_filter" "1" 6 \
    "Filtro de caminho reverso estrito (RFC 3704) para mitigar IP spoofing." \
    "Habilita Reverse Path Filtering em todas as interfaces."

audit_param "net.ipv4.conf.default.rp_filter" "1" 4 \
    "Filtro de caminho reverso estrito herdado por novas interfaces de rede." \
    "Habilita Reverse Path Filtering no perfil default de rede."

audit_param "net.ipv4.tcp_syncookies" "1" 7 \
    "Proteção contra saturação de fila de conexão TCP via ataques SYN Flood." \
    "Ativa SYN Cookies quando a fila de backlog TCP atinge saturação."

audit_param "net.ipv4.conf.all.accept_redirects" "0" 4 \
    "Bloqueia mensagens ICMP Redirect para impedir envenenamento de rotas." \
    "Desativa aceitação de pacotes ICMP Redirect."

audit_param "net.ipv4.conf.default.accept_redirects" "0" 3 \
    "Bloqueia mensagens ICMP Redirect no perfil padrão de novas interfaces." \
    "Desativa aceitação de ICMP Redirect no perfil default."

audit_param "net.ipv4.conf.all.send_redirects" "0" 3 \
    "Impede que o host atue indevidamente como roteador emitindo ICMP Redirects." \
    "Desativa o envio de redirecionamentos ICMP."

audit_param "net.ipv4.conf.all.accept_source_route" "0" 5 \
    "Bloqueia pacotes com Source Routing (roteamento na origem por atacantes)." \
    "Desativa aceitação de Source Route em pacotes IPv4."

audit_param "net.ipv4.icmp_echo_ignore_broadcasts" "1" 4 \
    "Ignora requisições de ping direcionadas a endereços de broadcast (mitigação Smurf)." \
    "Impede respostas a pings em broadcast."

audit_param "net.ipv4.icmp_ignore_bogus_error_responses" "1" 3 \
    "Protege contra avisos de erro malformados na pilha ICMP." \
    "Evita gravação e processamento de falsos erros ICMP."

audit_param "net.ipv4.conf.all.log_martians" "1" 3 \
    "Registra em log pacotes com endereços de IP inválidos ou impossíveis (Martian packets)." \
    "Habilita logging de pacotes marcianos."

# 2. Defesa de Rede IPv6
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo
    echo -e "${C_CYAN}[2/4] Defesa de Rede IPv6:${C_RESET}"
fi

audit_param "net.ipv6.conf.all.accept_redirects" "0" 4 \
    "Bloqueia mensagens ICMPv6 Redirect para impedir sequestro de rotas." \
    "Desativa aceitação de ICMPv6 Redirect."

audit_param "net.ipv6.conf.default.accept_redirects" "0" 3 \
    "Bloqueia ICMPv6 Redirect no perfil padrão de novas interfaces." \
    "Desativa aceitação de ICMPv6 Redirect no perfil default."

audit_param "net.ipv6.conf.all.accept_source_route" "0" 4 \
    "Bloqueia roteamento de origem em pacotes IPv6." \
    "Desativa aceitação de Source Route em IPv6."

# 3. Proteções do Sistema de Arquivos (Defesa contra Symlink/Hardlink Races em /tmp)
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo
    echo -e "${C_CYAN}[3/4] Sistema de Arquivos & Prevenção de Exploits de Link (/tmp):${C_RESET}"
fi

audit_param "fs.protected_hardlinks" "1" 6 \
    "Impede criação de hardlinks para arquivos cujo usuário não é proprietário." \
    "Bloqueia exploração de hardlinks em diretórios compartilhados com sticky bit."

audit_param "fs.protected_symlinks" "1" 6 \
    "Impede navegação e abertura de symlinks em diretórios graváveis por terceiros." \
    "Bloqueia ataques clássicos de symlink race condition (TOCTOU)."

audit_param "fs.protected_fifos" "2" 4 \
    "Restringe abertura de pipes nomeados (FIFOs) em diretórios globais abertos." \
    "Exige que o proprietário do FIFO seja o mesmo usuário do processo."

audit_param "fs.protected_regular" "2" 4 \
    "Impede criação e truncamento de arquivos regulares pertencentes a terceiros." \
    "Bloqueia sobrescrita de arquivos com O_CREAT em pastas compartilhadas."

audit_param "fs.suid_dumpable" "0" 5 \
    "Impede geração de core dumps por processos com privilégio SUID/SGID." \
    "Desativa despejo de memória com dados sensíveis de processos privilegiados."

# 4. Segurança do Kernel e Restrição de Memória (Anti-Exploits e Anti-ROP)
if [[ "${QUIET_MODE}" == "false" ]]; then
    echo
    echo -e "${C_CYAN}[4/4] Integridade do Kernel, Memória & Ocultação de Endereços:${C_RESET}"
fi

audit_param "kernel.randomize_va_space" "2" 8 \
    "Address Space Layout Randomization (ASLR) completo (pilha, heap e bibliotecas)." \
    "Configura ASLR em nível 2 (máxima aleatoriedade de espaço de memória)."

audit_param "kernel.kptr_restrict" "2" 6 \
    "Oculta ponteiros do kernel em /proc/kallsyms e logs contra ataques de ROP." \
    "Restringe visualização de endereços de kernel para mitigar exploits."

audit_param "kernel.dmesg_restrict" "1" 5 \
    "Restringe acesso ao buffer de mensagens do kernel (dmesg) exclusivamente ao root." \
    "Evita vazamento de informações operacionais e endereços de memória."

audit_param "kernel.unprivileged_bpf_disabled" "1" 5 \
    "Bloqueia compilação e carga de programas eBPF por usuários sem privilégio." \
    "Previne ataques de canal lateral (Spectre) via subsistema eBPF."

audit_param "kernel.sysrq" "0" 3 \
    "Desativa funções de debug de baixo nível via comandos mágicos de teclado SysRq." \
    "Bloqueia manipulação física não autorizada do console."

# ------------------------------------------------------------------------------
# Cálculo de Nota e Exibição de Resumo
# ------------------------------------------------------------------------------
GRADE="F"
if [[ "${TOTAL_SCORE}" -ge 95 ]]; then
    GRADE="A+"
elif [[ "${TOTAL_SCORE}" -ge 85 ]]; then
    GRADE="A"
elif [[ "${TOTAL_SCORE}" -ge 75 ]]; then
    GRADE="B"
elif [[ "${TOTAL_SCORE}" -ge 60 ]]; then
    GRADE="C"
elif [[ "${TOTAL_SCORE}" -ge 40 ]]; then
    GRADE="D"
fi

echo
echo -e "${C_BLUE}================================================================================${C_RESET}"
echo -e "${C_BOLD} SUMÁRIO DE CONFORMIDADE E HARDENING${C_RESET}"
echo -e "${C_BLUE}================================================================================${C_RESET}"
echo -e " Total de Parâmetros Auditados: ${TOTAL_CHECKS}"
echo -e "   [${C_GREEN}PASS${C_RESET}] Em conformidade estrita: ${PASS_COUNT}"
echo -e "   [${C_YELLOW}WARN${C_RESET}] Avisos / Parciais:        ${WARN_COUNT}"
echo -e "   [${C_RED}FAIL${C_RESET}] Falhas críticas:          ${FAIL_COUNT}"
echo -e "--------------------------------------------------------------------------------"
echo -e " Pontuação Técnica: ${C_BOLD}${TOTAL_SCORE}/${MAX_SCORE}${C_RESET} | Nota de Hardening: ${C_BOLD}${GRADE}${C_RESET}"
echo -e "${C_BLUE}================================================================================${C_RESET}"

if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
    echo
    echo -e "${C_BOLD}[*] Recomendações Prioritárias de Remediação:${C_RESET}"
    idx=1
    for rec in "${RECOMMENDATIONS[@]}"; do
        echo -e "  ${idx}. ${rec}"
        idx=$((idx + 1))
    done
fi

# ------------------------------------------------------------------------------
# Geração de Arquivo 99-sysctl-hardening.conf
# ------------------------------------------------------------------------------
if [[ "${GENERATE_CONF}" == "true" ]]; then
    echo
    echo -e "[+] Gerando arquivo de configuração em: ${C_WHITE}${CONF_OUTPUT}${C_RESET}..."
    cat > "${CONF_OUTPUT}" << 'EOF'
# ==============================================================================
# 99-sysctl-hardening.conf
# Gerado por: kernel-sysctl-check.sh (Rafael Soje - https://github.com/rafaelsoje)
# Padrões: CIS Linux Benchmark, NIST SP 800-128 e CISOfy Lynis
# ==============================================================================

# --- [1] Defesa de Rede IPv4 (Anti-Spoofing & Mitigação DoS) ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1

# --- [2] Defesa de Rede IPv6 ---
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0

# --- [3] Sistema de Arquivos & Proteção de Links (/tmp) ---
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0

# --- [4] Integridade do Kernel, ASLR & Ocultação de Memória ---
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
kernel.sysrq = 0
EOF
    echo -e "[OK] Arquivo de hardening gerado com sucesso: ${CONF_OUTPUT}"
    echo -e "    Para aplicar no sistema: sudo sysctl -p ${CONF_OUTPUT}"
fi

# ------------------------------------------------------------------------------
# Aplicação Direta (se solicitada com --apply)
# ------------------------------------------------------------------------------
if [[ "${APPLY_CHANGES}" == "true" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo -e "${C_RED}[ERRO] A opção '--apply' requer privilégios de superusuário (root). Execute com sudo.${C_RESET}" >&2
        exit 1
    fi

    echo
    echo -e "[+] Aplicando parâmetros de hardening no kernel em tempo de execução..."
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null
    sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null
    sysctl -w net.ipv4.conf.default.accept_redirects=0 >/dev/null
    sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null
    sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null
    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null
    sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 >/dev/null
    sysctl -w net.ipv4.conf.all.log_martians=1 >/dev/null

    sysctl -w net.ipv6.conf.all.accept_redirects=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.accept_redirects=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.all.accept_source_route=0 >/dev/null 2>&1 || true

    sysctl -w fs.protected_hardlinks=1 >/dev/null
    sysctl -w fs.protected_symlinks=1 >/dev/null
    sysctl -w fs.protected_fifos=2 >/dev/null
    sysctl -w fs.protected_regular=2 >/dev/null
    sysctl -w fs.suid_dumpable=0 >/dev/null

    sysctl -w kernel.randomize_va_space=2 >/dev/null
    sysctl -w kernel.kptr_restrict=2 >/dev/null
    sysctl -w kernel.dmesg_restrict=1 >/dev/null
    sysctl -w kernel.unprivileged_bpf_disabled=1 >/dev/null 2>&1 || true
    sysctl -w kernel.sysrq=0 >/dev/null

    echo -e "[OK] Todos os parâmetros foram aplicados com sucesso em tempo de execução."
fi
