# Huawei Switch Config Backup Utility

A bash-based CLI tool to automate configuration backups from Huawei VRP switches over SSH. Supports password and key-based authentication, per-switch credentials, structured output, and run logging.

---

## Sample Output

```
══════════════════════════════════════════════════════════
      Huawei Switch Backup  —  2026-06-28 10:07:13
══════════════════════════════════════════════════════════
  Config      switches.conf  (found 3 conf)
  Ping Check  enabled

  [1/3] SSH: username@172.1.2.3
  (*) PING    ........  UP
  (*) AUTH    ........  OK     (using Password)
  (*) FETCH   ........  OK     (Host: HUWAEI_ROUTERNAME)
  (*) WRITE   ........  OK     HUWAEI_ROUTERNAME_20260628_100713.cfg  (14.2 KB)

  [2/3] SSH: username@172.4.5.6
  (*) PING    ........  UP
  (*) AUTH    ........  FAIL   (wrong password or user)

  [3/3] SSH: username@172.7.8.9
  (*) PING    ........  DOWN   (host unreachable — skipping)

  ──────────────────────────────────────────────────────────
  RESULT  :  1 succeeded  ·  2 failed  ·  3 total
  ELAPSED :  9.3s
  OUTPUT  :  backups/20260628/
  LOGFILE :  log/take_backup_20260628_100713.log

  FAILED LIST:
    1.  username@172.4.5.6    :  authentication failed
    2.  username@172.7.8.9    :  no ping response
  ──────────────────────────────────────────────────────────
```

---

## Features

- Batch backup across multiple switches from a single config file
- Per-switch username and password support
- Password-less (SSH key) mode supported
- Passwords passed via environment variable — safe for special characters (`$`, `[`, `\`, `#`, etc.)
- ICMP reachability check before attempting SSH
- Hostname auto-detected from VRP prompt (`<SYSNAME>`) — used as filename
- Config output stripped of SSH session noise — starts cleanly from `Info:` line
- Distinct failure reasons: auth failed / connection refused / timed out / invalid config
- Aligned failed list in summary for easy review
- Full run log saved to `log/` directory
- Backup files organized under `backups/YYYYMMDD/`

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` | Shell interpreter |
| `expect` | SSH interaction and automation |
| `ssh` | Remote connection to switches |
| `ping` | Reachability check (optional) |
| `awk` | Text processing and file size calculation |

Install `expect` if not present:
```bash
# Debian / Ubuntu / WSL
sudo apt install expect

# RHEL / CentOS
sudo yum install expect
```

---

## Directory Structure

```
huawei-switch-backup/
├── take_backup.sh       # Main script
├── switches.conf        # Switch inventory (IP  USER  PASSWORD)
├── backups/             # Config backup output (auto-created)
│   └── YYYYMMDD/
│       └── SYSNAME_YYYYMMDD_HHMMSS.cfg
└── log/                 # Run logs (auto-created)
    └── take_backup_YYYYMMDD_HHMMSS.log
```

---

## Setup

**1. Clone the repo**
```bash
git clone https://github.com/thisisazharul-debug/huawei-switch-backup/huawei-switch-backup.git

cd huawei-switch-backup
```

**2. Make the script executable**
```bash
chmod +x take_backup.sh
```

**3. Create your `switches.conf`**
```bash
cp switches.conf.example switches.conf
```

Edit `switches.conf` with your switch details (see format below).

---

## switches.conf Format

```
# Format: IP   USERNAME   PASSWORD
# Use  -  as password for SSH key authentication

172.1.2.3      username   YourPassword123
172.4.5.6      username   AnotherPass456
172.17.32.9    username   -
```

- Lines starting with `#` are treated as comments and ignored
- Use `-` in the password column for passwordless (SSH key) authentication
- Passwords with special characters (`$`, `[`, `\`, `#`) are handled safely via environment variable

---

## Usage

```bash
./take_backup.sh
```

No arguments needed. The script reads `switches.conf` from the same directory and writes output to `backups/YYYYMMDD/`.

**To disable ping check** (useful if ICMP is blocked), edit the script:
```bash
TRY_PING=0
```

**To adjust SSH timeout:**
```bash
SSH_TIMEOUT=30   # seconds
```

---

## Output Files

Each backup is saved as:
```
backups/YYYYMMDD/SYSNAME_YYYYMMDD_HHMMSS.cfg
```

Example:
```
backups/20260628/HUWAEI_ROUTERNAME_20260628_100713.cfg
```

If the hostname cannot be parsed from the VRP prompt, the switch IP is used as the filename instead.

---

## Tested On

| Environment | Details |
|---|---|
| OS | Oracle Linux 9.7 (WSL2 on Windows 11) |
| Switch Platform | Huawei CloudEngine / S-Series (VRP V300R024) |
| Auth | TACACS+ password authentication |

---

## License

MIT License — free to use, modify, and distribute.
