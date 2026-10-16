# Linux Sysadmin & DevSecOps Toolbox 🐧🛡️

[![Bash](https://img.shields.io/badge/Language-Bash%20%2F%20POSIX-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%2F%20POSIX-FCC624?logo=linux&logoColor=black)](https://kernel.org/)
[![LPIC-1](https://img.shields.io/badge/Certified-LPIC--1-blue)](https://www.lpi.org/our-certifications/lpic-1-overview/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Security: Audited](https://img.shields.io/badge/Security-Sanitized%20%26%20Audited-brightgreen)](#segurança-e-boas-práticas)

Conjunto modular de ferramentas, scripts de automação, rotinas de contingência e templates `systemd` para administração de sistemas Linux em ambientes de produção, servidores VPS e cloud privada.

Desenvolvido por **[Rafael Soje](https://rafaelsoje.com)** — Administrador de Sistemas Linux (Certificado LPIC-1) e Especialista em Segurança da Informação.

---

## 📁 Estrutura do Repositório

```text
linux-sysadmin-toolbox/
├── backup/
│   ├── backup-hetzner-gfs.sh       # Rotina de backup GFS com hash SHA-256 e sincronização Rclone
│   ├── backup-mysql.sh             # Dump de bancos MySQL/MariaDB com compactação e retenção local
│   └── rclone-dedupe.sh            # Utilitário de desduplicação para remotes do Rclone
├── system/
│   ├── create-swap.sh              # Alocação segura de Swap com permissões 0600 e persistência no fstab
│   ├── sysinfo.sh                  # Relatório consolidado de hardware, kernel, carga e rede
│   └── userinfo.sh                 # Auditoria de usuários, diretório home, UID/GID e último login
├── network/
│   └── tor-proxy-manager.sh        # Alternador e verificador de proxy CLI SOCKS5 (Tor local)
├── systemd/
│   ├── backup-hetzner.service      # Unit do systemd para execução do backup
│   ├── backup-hetzner.timer        # Unit timer para agendamento diário automático
│   └── rclone-mount.service        # Unit para montagem de storage remoto via FUSE
├── LICENSE                         # Licença MIT
└── README.md                       # Documentação técnica de uso
```

---

## 🛠️ Ferramentas e Guias de Uso

### 1. Backup & Recuperação de Desastres (`backup/`)

#### 🔄 `backup-hetzner-gfs.sh`
Rotina de backup automatizada com validação de integridade por soma de verificação (hash SHA-256) e política de retenção **GFS (Grandfather-Father-Son)**:
* **Integridade Criptográfica**: Gera hash SHA-256 local antes do upload e valida diretamente contra a cópia remota no Rclone antes de limpar o espaço em disco.
* **Política GFS**:
  * **Diário (Son)**: Mantido por 7 dias.
  * **Semanal (Father)**: Promovido aos domingos, retido por 30 dias.
  * **Mensal (Grandfather)**: Promovido no dia 01 de cada mês, retido por 180 dias.
  * **Anual**: Promovido no dia 01 de janeiro, retido por 2 anos.

```bash
# Execução direta utilizando valores padrão
chmod +x backup/backup-hetzner-gfs.sh
./backup/backup-hetzner-gfs.sh

# Customização via variáveis de ambiente
BACKUP_DIR="/mnt/storage/temp" \
REMOTE="meu-storage-box" \
BACKUP_SOURCES="/etc /var/www /home/dados" \
./backup/backup-hetzner-gfs.sh
```

#### 🗄️ `backup-mysql.sh`
Geração de dumps consistentes do MySQL ou MariaDB sem credenciais expostas no código:
* Suporta autenticação segura via `~/.my.cnf` (permissão `600`) ou variáveis de ambiente padrão (`MYSQL_USER`, `MYSQL_PWD`, `MYSQL_HOST`).
* Compactação `gzip -9` em pipeline sem criar arquivos intermediários não compactados em disco.
* Rotação e limpeza automática de dumps com mais de *N* dias.

```bash
# Fazer backup de todos os bancos com retenção de 14 dias
chmod +x backup/backup-mysql.sh
./backup/backup-mysql.sh

# Fazer backup de um banco específico
MYSQL_DATABASE="nome_do_banco" RETENTION_DAYS=30 ./backup/backup-mysql.sh
```

#### 📦 `rclone-dedupe.sh`
Elimina arquivos duplicados em contas de nuvem (Google Drive, Nextcloud, S3, Hetzner, etc.):
```bash
./backup/rclone-dedupe.sh "drive:MeusArquivos" oldest
```

---

### 2. Gerenciamento e Diagnóstico de Sistema (`system/`)

#### 💾 `create-swap.sh`
Criação segura de arquivo de paginação (Swap File) no Linux:
* Verifica swap pré-existente no kernel.
* Aloca com `fallocate` de alta performance ou fallback automático para `dd` em sistemas de arquivos que não suportam pré-alocação (como certos volumes XFS/Btrfs).
* Aplica permissões restritas `0600` para conformidade de segurança e formata com `mkswap`.
* Registra persistentemente em `/etc/fstab` apenas se a entrada ainda não existir (evitando duplicatas).

```bash
# Criar swap de 4 GB como root
sudo ./system/create-swap.sh 4G /swapfile
```

#### 📊 `sysinfo.sh`
Gera relatório instantâneo de diagnóstico do servidor:
* Versão exata do Kernel e arquitetura.
* Uptime legível e Load Average em 1m, 5m e 15m.
* Quantidade de cores físicos/lógicos e modelo da CPU.
* Consumo consolidado de RAM e Swap.
* Partições montadas (excluindo loops/squashfs do snap e tmpfs).
* Interfaces de rede e IPs atribuídos.

```bash
./system/sysinfo.sh
```

#### 👤 `userinfo.sh`
Audita contas locais no sistema para compliance e conformidade de privilégios:
```bash
./system/userinfo.sh rafael
```

---

### 3. Rede e Anonimização (`network/`)

#### 🧅 `tor-proxy-manager.sh`
Ativação e verificação de conectividade via rede Tor através do túnel SOCKS5 local (`127.0.0.1:9050`):
```bash
# Testar integridade da conexão Tor:
./network/tor-proxy-manager.sh status

# Exportar variáveis de proxy para a sessão do terminal atual:
source ./network/tor-proxy-manager.sh on

# Desativar proxy:
source ./network/tor-proxy-manager.sh off
```

---

### 4. Automação via Systemd (`systemd/`)

O diretório `systemd/` disponibiliza arquivos de unidade prontos para produção:

1. **Agendamento de Backup**: Copie `backup-hetzner.service` e `backup-hetzner.timer` para `/etc/systemd/system/`:
```bash
sudo cp systemd/backup-hetzner.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup-hetzner.timer
sudo systemctl list-timers --all
```

2. **Montagem Persistente Rclone**:
```bash
sudo cp systemd/rclone-mount.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rclone-mount.service
```

---

## 🔒 Segurança e Boas Práticas

* **Zero Hardcoded Secrets**: Nenhuma credencial ou token reside no código. Todas as autenticações utilizam variáveis de ambiente ou arquivos de configuração protegidos por permissão POSIX (`0600`).
* **POSIX / Bash Safe Mode**: Todos os scripts utilizam `set -euo pipefail` para interrupção imediata em caso de falha silenciosa, variáveis não declaradas ou erros em pipelines.
* **Validação Pré-Execução**: Verificação prévia de dependências no host (`rclone`, `mysqldump`, `fallocate`, `awk`, `sha256sum`).

---

## 👤 Autor

**Rafael Soje**
* **Website Oficial**: [rafaelsoje.com](https://rafaelsoje.com)
* **GitHub**: [@rafaelsoje](https://github.com/rafaelsoje)
* **Certificação**: LPIC-1 (Linux Professional Institute)
* **Especialidade**: Linux System Administration, DevSecOps, Segurança da Informação e Arquitetura Web.
