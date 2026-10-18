# Linux Sysadmin & DevSecOps Toolbox 🐧🛡️

[![Bash](https://img.shields.io/badge/Language-Bash%20%2F%20POSIX-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/Language-Python%203-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%2F%20POSIX-FCC624?logo=linux&logoColor=black)](https://kernel.org/)
[![Security: Hardened](https://img.shields.io/badge/Security-HIDS%20%26%20WAF%20Hardened-red)](#5-segurança-hardening--hids-security-hardening)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Conjunto modular de ferramentas de produção, scripts de automação, rotinas de contingência GFS, sistemas de detecção de intrusão baseados em host (HIDS) e automação de WAF/Fail2ban para administração de servidores Linux e VPS em alta disponibilidade.

Desenvolvido por **[Rafael Soje](https://rafaelsoje.com)** — Administrador de Sistemas Linux e Especialista em Segurança da Informação & DevSecOps.

---

## 📁 Estrutura do Repositório

```text
linux-sysadmin-toolbox/
├── backup/
│   ├── backup-hetzner-gfs.sh                 # Rotina de backup GFS com hash SHA-256 e sincronização Rclone
│   ├── backup-mysql.sh                       # Dump seguro de MySQL/MariaDB com gzip e retenção local
│   └── rclone-dedupe.sh                      # Desduplicação automatizada em remotes Rclone
├── system/
│   ├── create-swap.sh                        # Alocação de Swap com permissões 0600 e persistência no fstab
│   ├── sysinfo.sh                            # Diagnóstico consolidado de hardware, kernel, carga e rede
│   └── userinfo.sh                           # Auditoria de contas locais, diretório home, UID/GID e lastlog
├── network/
│   └── tor-proxy-manager.sh                  # Gerenciador CLI de proxy SOCKS5 (Tor local)
├── security-hardening/
│   ├── config.example.env                    # Template seguro para credenciais de API e alertas
│   ├── update-abuseipdb-cloudflare.py        # Sincronizador diário de reputação AbuseIPDB -> Cloudflare WAF Lists
│   ├── f2b-nginx-cloudflare-block.py         # Bloqueio em camada dupla (Nginx RealIP map + Cloudflare Edge WAF)
│   ├── f2b-telegram-notify.py                # Alertas forenses via Telegram com análise de probes e força bruta SSH
│   └── hids/
│       ├── chat-telegram.sh                  # Script universal de alertas via Telegram Bot API
│       ├── monitorar-portas.sh               # Monitoramento com diff de portas abertas (críticas vs essenciais)
│       ├── monitorar-pacotes.sh              # Auditoria de pacotes instalados/removidos via dpkg
│       ├── arquivos-criticos-fim.sh          # File Integrity Monitoring (FIM) com hashes SHA-256 e exclusões
│       └── monitorar-bits-especiais.sh       # Detecção de novos binários com bits especiais SUID/SGID
├── systemd/
│   ├── backup-hetzner.service                # Unit systemd para rotina de backup
│   ├── backup-hetzner.timer                  # Agendamento diário do backup (03:00)
│   ├── abuseipdb-sync.service                # Unit systemd para sincronização com Cloudflare WAF
│   ├── abuseipdb-sync.timer                  # Agendamento diário de reputação (04:00)
│   └── rclone-mount.service                  # Unit para montagem de storage remoto via FUSE
├── LICENSE                                   # Licença MIT
└── README.md                                 # Documentação técnica completa
```

---

## 🛠️ Ferramentas e Guias de Uso

### 1. Backup & Recuperação de Desastres (`backup/`)

#### 🔄 `backup-hetzner-gfs.sh`
Rotina de backup automatizada com verificação criptográfica de integridade por **hash SHA-256** e política de retenção **GFS (Grandfather-Father-Son)**:
* **Integridade Criptográfica**: Gera hash SHA-256 local antes do envio e valida diretamente contra a cópia remota no Rclone antes de expurgar arquivos temporários locais.
* **Política GFS**:
  * **Diário (Son)**: Mantido por 7 dias.
  * **Semanal (Father)**: Promovido aos domingos, retido por 30 dias.
  * **Mensal (Grandfather)**: Promovido no dia 01, retido por 180 dias.
  * **Anual**: Promovido no dia 01 de janeiro, retido por 2 anos.

```bash
chmod +x backup/backup-hetzner-gfs.sh
./backup/backup-hetzner-gfs.sh
```

#### 🗄️ `backup-mysql.sh`
Dump consistente de bancos MySQL/MariaDB sem credenciais expostas no código:
* Autenticação segura via `~/.my.cnf` (permissão `0600`) ou variáveis de ambiente (`MYSQL_USER`, `MYSQL_PWD`, `MYSQL_HOST`).
* Compactação `gzip -9` em pipeline sem overhead de arquivos temporários descompactados em disco.
* Rotação e expurgo automático de dumps locais com mais de *N* dias.

---

### 2. Gerenciamento e Diagnóstico de Sistema (`system/`)

#### 💾 `create-swap.sh`
Criação automatizada de Swap File no Linux:
* Aloca com `fallocate` de alta performance ou fallback automático para `dd`.
* Aplica permissões restritas `0600` e formata com `mkswap`.
* Registra persistentemente em `/etc/fstab` com prevenção contra entradas duplicadas.

```bash
sudo ./system/create-swap.sh 4G /swapfile
```

#### 📊 `sysinfo.sh`
Relatório instantâneo de diagnóstico do servidor: Kernel, arquitetura, Uptime, Load Average, Cores da CPU, consumo consolidado de RAM/Swap, particionamento e interfaces de rede.

#### 👤 `userinfo.sh`
Audita contas locais no sistema para conformidade de privilégios (UID, GID, grupos, espaço em uso na home e último login via `lastlog`).

---

### 3. Rede e Anonimização (`network/`)

#### 🧅 `tor-proxy-manager.sh`
Ativação e verificação de conectividade via rede Tor através do túnel SOCKS5 local (`127.0.0.1:9050`):
```bash
# Testar conectividade:
./network/tor-proxy-manager.sh status

# Exportar variáveis para a sessão atual do shell:
source ./network/tor-proxy-manager.sh on
```

---

### 4. Segurança, Hardening & HIDS (`security-hardening/`)

Módulo avançado de proteção perimetral, integração de WAF na borda e detecção de intrusão local:

#### ☁️ `update-abuseipdb-cloudflare.py`
Sincroniza automaticamente a blacklist de reputação global do **AbuseIPDB** com as listas de regras customizadas do **Cloudflare WAF (IP Lists)**:
* Baixa até 10.000 IPs maliciosos com pontuação de abuso $\ge 90\%$.
* Tratamento automático de rate limits (HTTP 429) com parsing do cabeçalho `X-RateLimit-Reset`.
* Upload em lote via API v4 do Cloudflare com monitoramento da operação assíncrona.

#### 🧱 `f2b-nginx-cloudflare-block.py`
Integração de resposta ativa do Fail2ban com bloqueio em camada dupla:
1. **Camada de Borda (Cloudflare WAF)**: Cria regra de bloqueio direto na API do Cloudflare, impedindo que o tráfego malicioso consuma largura de banda do VPS.
2. **Camada Local (Nginx RealIP)**: Mantém um mapa em memória (`blocked.map`) alimentado pelo Fail2ban para descartar conexões instantaneamente com HTTP 444.

#### 🚨 `f2b-telegram-notify.py`
Notificador de incidentes de segurança com extração forense:
* Analisa logs do Nginx para extrair os exatos payloads/rotas sensíveis sondadas (`.env`, `.git`, AWS, ModSecurity 403).
* Analisa o journal do `sshd` para listar quais nomes de usuários foram tentados no ataque de força bruta.
* Emite alertas imediatos no Telegram com nível de severidade e tempo de banimento.

#### 🌐 Regras de Borda do Cloudflare WAF (`cloudflare-waf-rules.json`)
Definições exportadas das regras personalizadas de proteção em borda (Cloudflare WAF Custom Rules):
1. **`Block by IP Lists: malicious_ips`**: Bloqueio ativo alimentado dinamicamente pelo script `update-abuseipdb-cloudflare.py`.
2. **`Bots e Crawlers de Ferramentas de Pentest / Scanner`**: Bloqueio de User-Agents maliciosos (Nikto, Nmap, SQLmap, Acunetix, WPScan, Dirbuster, Scrapy, etc.).
3. **`Acesso a Arquivos e Diretórios Críticos`**: Bloqueio perimetral de requisições a `.env`, `.git`, `.yaml`, `.sql`, backups (`.bak`, `.tar.gz`), `/actuator`, `phpmyadmin` e painéis administrativos.
4. **`Transversal Path | XSS | SQLi | Wrappers SSRF | Command Injection`**: Interceptação em camada de borda contra Path Traversal (`../`, URL encoded `%2e%2e%2f`), SQL Injection (`union select`, `sleep()`), XSS (`<script>`), PHP stream wrappers (`php://`, `gopher://`) e Command Injection (`;id`, `;cat`, `;bash`).


#### 🔍 HIDS (Host-Based Intrusion Detection System - `security-hardening/hids/`)
* **`monitorar-portas.sh`**: Monitoramento contínuo das portas em escuta (`ss -tunlp`). Emite alerta imediato caso portas críticas (21, 23, 25, 8080) sejam abertas ou portas vitais (22, 443) fiquem indisponíveis.
* **`monitorar-pacotes.sh`**: Auditoria do gerenciador de pacotes (`dpkg`), alertando sobre instalação ou remoção inadvertida de softwares e binários.
* **`arquivos-criticos-fim.sh`**: **File Integrity Monitoring (FIM)** baseado em checksums SHA-256 de diretórios sensíveis (`/etc/nginx`, `/etc/ssh`, etc.), detectando injeção de web shells, backdoors ou adulterações de configuração.
* **`monitorar-bits-especiais.sh`**: Rastreia binários com permissões especiais `SUID` (4000) e `SGID` (2000), identificando potenciais vetores de escalada de privilégios.

---

### 5. Automação via Systemd (`systemd/`)

Arquivos de unidade prontos para produção:
* **`backup-hetzner.service` / `.timer`**: Executa a rotina GFS diariamente às 03:00.
* **`abuseipdb-sync.service` / `.timer`**: Atualiza a lista do Cloudflare WAF diariamente às 04:00.
* **`rclone-mount.service`**: Montagem persistente de volumes em nuvem com cache VFS.

```bash
# Exemplo de ativação de timer:
sudo cp systemd/abuseipdb-sync.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now abuseipdb-sync.timer
```

---

## 🔒 Segurança e Boas Práticas

* **Zero Hardcoded Secrets**: Nenhuma credencial, token do Telegram ou chave de API reside no código. Todas as configurações utilizam variáveis de ambiente ou arquivos `config.env` protegidos com permissão `0600`.
* **POSIX / Bash Safe Mode**: Todos os scripts utilizam `set -euo pipefail` para interrupção imediata em caso de falha em pipes ou variáveis não declaradas.
* **Defesa em Profundidade**: Proteção combinando borda (Cloudflare), WAF aplicacional (ModSecurity / Nginx) e monitoramento de integridade do host (HIDS).

---

## 👤 Autor

**Rafael Soje**
* **Website Oficial**: [rafaelsoje.com](https://rafaelsoje.com)
* **GitHub**: [@rafaelsoje](https://github.com/rafaelsoje)
* **Especialidade**: Linux System Administration, DevSecOps, Segurança da Informação e Arquitetura Web.
