# Linux Sysadmin & DevSecOps Toolbox

[ [Versão em Português](README.md) ] • [ English ]

[![CI](https://github.com/rafaelsoje/linux-sysadmin-toolbox/actions/workflows/ci.yml/badge.svg)](https://github.com/rafaelsoje/linux-sysadmin-toolbox/actions)
[![Release](https://img.shields.io/badge/Release-v1.0.0-blue.svg)](https://github.com/rafaelsoje/linux-sysadmin-toolbox/releases/latest)
[![Bash](https://img.shields.io/badge/Language-Bash%20%2F%20POSIX-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/Language-Python%203-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%2F%20POSIX-FCC624?logo=linux&logoColor=black)](https://kernel.org/)
[![Security: Hardened](https://img.shields.io/badge/Security-HIDS%20%26%20WAF%20Hardened-red)](#4-security-hardening--hids-security-hardening)
[![XERJ Corpus Hub](https://img.shields.io/badge/XERJ_Corpus_Hub-Selected_Reference-7c3aed?logo=rust&logoColor=white)](https://github.com/xerj-org/xerj)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Modular suite of production tools, automation scripts, GFS contingency routines, host-based intrusion detection systems (HIDS), and WAF/Fail2ban automations for Linux servers and high-availability VPS administration.

> [!NOTE]
> **Community & AI Ecosystem Recognition:**  
> This repository was selected and integrated into the official **Corpus Hub** of [XERJ](https://github.com/xerj-org/xerj) (+18,000 GitHub stars) as an open-source reference implementation for Shell/Python automation, Nginx hardening, Docker hygiene, and host-based intrusion detection (HIDS) for autonomous AI programming agents.

Developed by **[Rafael Soje](https://rafaelsoje.com)** — Linux Systems Engineer and Information Security & DevSecOps Specialist.

---

## Repository Structure

```text
linux-sysadmin-toolbox/
├── backup/
│   ├── backup-hetzner-gfs.sh                 # GFS backup routine with SHA-256 integrity check and Rclone sync
│   ├── backup-mysql.sh                       # Safe MySQL/MariaDB dump with gzip pipeline and local retention
│   └── rclone-dedupe.sh                      # Automated deduplication across Rclone remotes
├── system/
│   ├── create-swap.sh                        # Swap allocation with 0600 permissions and fstab persistence
│   ├── docker-cleanup.sh                     # Docker hygiene with container log truncation (>50MB)
│   ├── sysinfo.sh                            # Consolidated hardware, kernel, load average, and network audit
│   └── userinfo.sh                           # Local account audit, home directories, UID/GID, and lastlog
├── network/
│   └── tor-proxy-manager.sh                  # CLI manager for local SOCKS5 proxy (Tor network)
├── security-hardening/
│   ├── config.example.env                    # Secure template for API credentials and alerts
│   ├── setup-hids.sh                         # Automated installer and baseline initializer for HIDS suite
│   ├── ssh-hardening-check.sh                # OpenSSH server compliance & hardening auditor (sshd_config)
│   ├── nginx-hardening.conf                  # Production-grade defensive security headers & directives
│   ├── cloudflare-waf-rules.json             # Custom edge security rules exported from Cloudflare WAF
│   ├── update-abuseipdb-cloudflare.py        # Daily sync: AbuseIPDB reputation -> Cloudflare WAF Lists
│   ├── f2b-nginx-cloudflare-block.py         # Dual-layer response (Nginx RealIP map + Cloudflare Edge WAF)
│   ├── f2b-telegram-notify.py                # Forensic Telegram alerts with probe inspection & brute-force data
│   └── hids/
│       ├── chat-telegram.sh                  # Universal alerting script via Telegram Bot API
│       ├── monitorar-portas.sh               # Continuous listening ports audit with diff analysis (ss)
│       ├── monitorar-pacotes.sh              # Package management audit via dpkg
│       ├── arquivos-criticos-fim.sh          # File Integrity Monitoring (FIM) with SHA-256 hashes
│       └── monitorar-bits-especiais.sh       # SUID/SGID special bits privilege escalation tracker
├── systemd/
│   ├── backup-hetzner.service                # Systemd unit for GFS backup routine
│   ├── backup-hetzner.timer                  # Daily backup timer (03:00)
│   ├── abuseipdb-sync.service                # Systemd unit for Cloudflare WAF synchronization
│   ├── abuseipdb-sync.timer                  # Daily reputation sync timer (04:00)
│   └── rclone-mount.service                  # Systemd unit for remote cloud storage mount with VFS cache
├── LICENSE                                   # MIT License
├── README.md                                 # Documentation in Portuguese
└── README.en.md                              # Documentation in English
```

---

## Tools and Usage Guides

### 1. Backup & Disaster Recovery (`backup/`)

#### `backup-hetzner-gfs.sh`
Automated backup routine featuring **SHA-256 cryptographic verification** and **Grandfather-Father-Son (GFS)** retention policies:
* **Cryptographic Integrity**: Generates a local SHA-256 hash before transmission and validates it directly against the remote Rclone replica before purging local temporary files.
* **GFS Retention Policy**:
  * **Daily (Son)**: Retained for 7 days.
  * **Weekly (Father)**: Promoted on Sundays, retained for 30 days.
  * **Monthly (Grandfather)**: Promoted on the 1st day of the month, retained for 180 days.
  * **Yearly**: Promoted on January 1st, retained for 2 years.

```bash
chmod +x backup/backup-hetzner-gfs.sh
./backup/backup-hetzner-gfs.sh
```

#### `backup-mysql.sh`
Consistent MySQL/MariaDB database dump without code-exposed credentials:
* Secure authentication via `~/.my.cnf` (`0600` permissions) or environment variables (`MYSQL_USER`, `MYSQL_PWD`, `MYSQL_HOST`).
* High-compression `gzip -9` stream pipeline with zero temporary uncompressed disk footprint.
* Automated local dump rotation and cleanup for archives older than *N* days.

---

### 2. System Management & Diagnostics (`system/`)

#### `create-swap.sh`
Automated swap file creation and persistence:
* Allocates with high-performance `fallocate` or automatic fallback to `dd`.
* Enforces strict `0600` permissions and formats via `mkswap`.
* Persistently registers inside `/etc/fstab` with duplicate entry prevention.

```bash
sudo ./system/create-swap.sh 4G /swapfile
```

#### `docker-cleanup.sh`
Routine Docker hygiene and disk space reclamation:
* Prunes stopped containers, dangling images, and orphan networks.
* Cleans BuildKit build cache.
* Truncates oversized container JSON log files (`*-json.log`) without stopping active services.

```bash
# Standard execution (cleanup with log truncation > 50MB):
sudo ./system/docker-cleanup.sh

# Dry-run inspection without applying changes:
./system/docker-cleanup.sh --dry-run
```

#### `sysinfo.sh`
Instant server diagnostic report: Kernel, architecture, Uptime, Load Average, CPU Cores, RAM/Swap metrics, filesystem partitions, and active network interfaces.

#### `userinfo.sh`
Local account security audit: UID, GID, groups, home directory usage, and last login via `lastlog`.

---

### 3. Networking & Anonymization (`network/`)

#### `tor-proxy-manager.sh`
Activation and status check for Tor SOCKS5 proxy tunnel (`127.0.0.1:9050`):
```bash
# Test connectivity:
./network/tor-proxy-manager.sh status

# Export proxy environment variables to the active shell:
source ./network/tor-proxy-manager.sh on
```

---

### 4. Security Hardening & HIDS (`security-hardening/`)

Advanced perimeter protection, edge WAF orchestration, and host-based intrusion detection:

#### `update-abuseipdb-cloudflare.py`
Synchronizes the **AbuseIPDB** global threat intelligence blacklist directly into **Cloudflare WAF IP Lists**:
* Downloads up to 10,000 malicious IPs with abuse confidence score $\ge 90\%$.
* Handles rate limits automatically (HTTP 429) using `X-RateLimit-Reset` header parsing.
* Batched upload via Cloudflare API v4 with async operation monitoring.

#### `f2b-nginx-cloudflare-block.py`
Active intrusion response integrating Fail2ban with dual-layer mitigation:
1. **Edge Layer (Cloudflare WAF)**: Creates instantaneous edge block rules, preventing malicious traffic from reaching the VPS.
2. **Local Layer (Nginx RealIP)**: Populates an in-memory map (`blocked.map`) to drop abusive requests immediately with HTTP 444.

#### `f2b-telegram-notify.py`
Incident alert dispatcher with automated forensic extraction:
* Analyzes Nginx logs to pinpoint targeted routes (`.env`, `.git`, AWS credentials, ModSecurity 403).
* Inspects `sshd` journal logs to extract attempted usernames in brute-force attacks.
* Dispatches real-time Telegram alerts with severity ratings and ban durations.

#### Cloudflare WAF Edge Rules (`cloudflare-waf-rules.json`)
Exported production rules for Cloudflare WAF:
1. **`Block by IP Lists: malicious_ips`**: Edge blocking populated by `update-abuseipdb-cloudflare.py`.
2. **`Pentest & Scanner User-Agents`**: Intercepts scanners (Nikto, Nmap, SQLmap, Acunetix, WPScan, Dirbuster, Scrapy, etc.).
3. **`Critical File & Directory Protection`**: Blocks requests targeting `.env`, `.git`, `.yaml`, `.sql`, backups (`.bak`, `.tar.gz`), `/actuator`, `phpmyadmin`, and administrative interfaces.
4. **`Path Traversal | XSS | SQLi | SSRF | Command Injection`**: Intercepts path traversal (`../`, `%2e%2e%2f`), SQL Injection (`union select`, `sleep()`), XSS (`<script>`), PHP stream wrappers (`php://`), and command injection (`;id`, `;cat`).

#### `nginx-hardening.conf`
Modular Nginx snippet for production environments:
* Modern security headers: HSTS (`max-age=31536000`), X-Frame-Options, X-Content-Type-Options, and Permissions-Policy.
* Server token obfuscation (`server_tokens off`).
* Silent drops (HTTP 444) for dotfiles and backup archives.
* Hardened buffers against slow-rate resource exhaustion attacks (Slowloris).

#### `setup-hids.sh`
Interactive HIDS suite installer:
* Creates directory hierarchies and configuration skeletons.
* Generates initial cryptographic host baselines in `/home/$USER/.hids/logs/`.
* Displays ready-to-use cron and systemd schedules.

```bash
./security-hardening/setup-hids.sh
```

#### `ssh-hardening-check.sh`
Compliance and hardening auditor for **OpenSSH Server** (`sshd_config`), based on CIS Benchmarks and NIST SP 800-128:
* **Dual Inspection Engine**: Uses native OpenSSH engine (`sshd -T`) when executed with appropriate privileges or recursive parsing across `Include` directives (`sshd_config.d/*.conf`).
* **Audited Directives**:
  * Root Login Policy (`PermitRootLogin no`)
  * Key vs Password Authentication (`PasswordAuthentication no`, `PubkeyAuthentication yes`)
  * Empty Password Rejection (`PermitEmptyPasswords no`)
  * Brute-Force Rate Limiting (`MaxAuthTries 3`)
  * Forwarding Restrictions (`X11Forwarding no`, `AllowAgentForwarding no`)
  * Idle Session Timeout (`ClientAliveInterval`, `ClientAliveCountMax`)
  * Legacy Protocol Blocking (`HostbasedAuthentication no`, `IgnoreRhosts yes`)
  * Obsolete Cryptographic Suite Detection (3DES, Arcfour, Blowfish, MD5, DH-Group1)
* **Diagnostics & Reporting**:
  * Technical score (0 to 100) and letter grade (A+, A, B, C, D, F).
  * Prioritized remediation checklist.
  * Supports arbitrary configuration files (`-c`) and no-color mode (`--no-color`).

```bash
# Audit active system configuration:
./security-hardening/ssh-hardening-check.sh

# Audit custom configuration file or backup:
./security-hardening/ssh-hardening-check.sh -c /etc/ssh/sshd_config
```

#### HIDS (Host-Based Intrusion Detection System - `security-hardening/hids/`)
* **`monitorar-portas.sh`**: Continuous monitoring of listening ports (`ss -tunlp`). Alerts on suspicious open ports (21, 23, 25, 8080) or essential port downtime (22, 443).
* **`monitorar-pacotes.sh`**: Package manager audit (`dpkg`), tracking additions and removals.
* **`arquivos-criticos-fim.sh`**: **File Integrity Monitoring (FIM)** based on SHA-256 hashes of sensitive paths (`/etc/nginx`, `/etc/ssh`), detecting webshell injection or backdoor modifications.
* **`monitorar-bits-especiais.sh`**: Privilege escalation tracker monitoring `SUID` (4000) and `SGID` (2000) binaries.

---

### 5. Automation via Systemd (`systemd/`)

Production-ready unit files:
* **`backup-hetzner.service` / `.timer`**: Runs GFS routine daily at 03:00.
* **`abuseipdb-sync.service` / `.timer`**: Updates Cloudflare WAF list daily at 04:00.
* **`rclone-mount.service`**: Persistent cloud storage mount with VFS cache.

```bash
# Example timer activation:
sudo cp systemd/abuseipdb-sync.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now abuseipdb-sync.timer
```

---

## Security & Best Practices

* **Zero Hardcoded Secrets**: No credentials, Telegram tokens, or API keys reside in code. All configuration uses environment variables or `config.env` files secured with `0600` permissions.
* **POSIX / Bash Safe Mode**: All shell scripts execute with `set -euo pipefail` to ensure immediate termination on errors, uninitialized variables, or pipe failures.
* **Defense in Depth**: Multi-tier architecture combining edge protection (Cloudflare), web application firewall (Nginx / ModSecurity), and host integrity monitoring (HIDS).

---

## Author

**Rafael Soje**
* **Official Website**: [rafaelsoje.com](https://rafaelsoje.com)
* **GitHub**: [@rafaelsoje](https://github.com/rafaelsoje)
* **Specialization**: Linux Systems Administration, DevSecOps, Information Security & Web Architecture.
