#!/usr/bin/env bash
# =============================================================
#  Huawei Switch Config Backup Utility
#  Author  : Azharul Islam <bd.islam.azharul@gmail.com>
#  GitHub  : https://github.com/bdislamazharul
#  Version : 1.0.0
#  Config file : switches.conf  (IP  USER  PASSWORD)
#  Output      : ./backups/YYYYMMDD/
#  Log         : ./log/
#  =============================================================

CONF_FILE="switches.conf"
BACKUP_DIR="backups/$(date +%Y%m%d)"
LOG_DIR="log"
LOG_FILE="${LOG_DIR}/take_backup_$(date +%Y%m%d_%H%M%S).log"
SSH_TIMEOUT=30
TRY_PING=1          # 1 = ping before SSH, 0 = skip ping check

# ---------- colors ----------
RESET="\033[0m"
BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
DIM="\033[2m"

# ---------- separators ----------
DSEP="══════════════════════════════════════════════════════════"
SSEP="──────────────────────────────────────────────────────────"

# ---------- helpers ----------
now() { date '+%Y-%m-%d %H:%M:%S'; }

# log to both terminal and log file
tlog() { echo -e "$@" | tee -a "$LOG_FILE"; }

step_line() {
    local label="$1"
    local status="$2"
    local detail="$3"
    printf -v LINE "  (*) %-7s ........  %-6s %s" "$label" "$status" "$detail"
    echo -e "$LINE" | tee -a "$LOG_FILE"
}

filesize() {
    local bytes
    bytes=$(wc -c < "$1" 2>/dev/null || echo 0)
    if   [[ $bytes -ge 1048576 ]]; then awk "BEGIN {printf \"%.1f MB\", $bytes/1048576}"
    elif [[ $bytes -ge 1024 ]];    then awk "BEGIN {printf \"%.1f KB\", $bytes/1024}"
    else printf "%d B" "$bytes"
    fi
}

# ---------- elapsed ----------
START_TS=$(date +%s%N)
elapsed() {
    local diff_ms
    diff_ms=$(( ($(date +%s%N) - START_TS) / 1000000 ))
    awk "BEGIN {printf \"%.1fs\", $diff_ms/1000}"
}

# ---------- setup dirs ----------
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

# ---------- banner ----------
tlog ""
tlog "${BOLD}${CYAN}${DSEP}${RESET}"
tlog "${BOLD}${CYAN}      Huawei Switch Backup  —  $(now)${RESET}"
tlog "${BOLD}${CYAN}${DSEP}${RESET}"

# ---------- read config ----------
if [[ ! -f "$CONF_FILE" ]]; then
    tlog "${RED}ERROR: Config file '$CONF_FILE' not found.${RESET}"
    exit 1
fi

mapfile -t SWITCHES < <(grep -v '^\s*#' "$CONF_FILE" | grep -v '^\s*$')
TOTAL=${#SWITCHES[@]}

if [[ $TOTAL -eq 0 ]]; then
    tlog "${RED}ERROR: No switches found in '$CONF_FILE'.${RESET}"
    exit 1
fi

tlog "  Config      ${CONF_FILE}  (found ${BOLD}${TOTAL}${RESET} conf)"
tlog "  Ping Check  $([ "$TRY_PING" -eq 1 ] && echo "enabled" || echo "disabled")"

SUCCESS=0
FAILED=0
FAILED_LIST=()

# ---------- loop ----------
for i in "${!SWITCHES[@]}"; do
    INDEX=$((i + 1))
    LINE="${SWITCHES[$i]}"

    SWIP=$(echo   "$LINE" | awk '{print $1}')
    SWUSER=$(echo "$LINE" | awk '{print $2}')
    SWPASS=$(echo "$LINE" | awk '{print $3}')

    AUTH_MODE="password"
    [[ "$SWPASS" == "-" || -z "$SWPASS" ]] && AUTH_MODE="key"

    tlog ""
    tlog "  ${BOLD}${YELLOW}[${INDEX}/${TOTAL}] SSH: ${SWUSER}@${SWIP}${RESET}"

    # ---------- ping ----------
    if [[ "$TRY_PING" -eq 1 ]]; then
        if ping -c 1 -W 2 "$SWIP" > /dev/null 2>&1; then
            step_line "PING" "${GREEN}UP${RESET}" ""
        else
            step_line "PING" "${RED}DOWN${RESET}" "${RED}(host unreachable — skipping)${RESET}"
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("${SWUSER}@${SWIP}  :  no ping response")
            continue
        fi
    fi

    # ---------- build expect script ----------
    export _SW_PASS="$SWPASS"

    if [[ "$AUTH_MODE" == "key" ]]; then
        EXPECT_SCRIPT=$(cat << EOF
log_user 1
set timeout $SSH_TIMEOUT

spawn ssh -o StrictHostKeyChecking=no \
          -o ConnectTimeout=10 \
          ${SWUSER}@${SWIP}

expect {
    -re {<[^>]+>}            {}
    "password:"              { puts "ERR_AUTH"; exit 1 }
    "Authentication failed"  { puts "ERR_AUTH"; exit 1 }
    "Permission denied"      { puts "ERR_AUTH"; exit 1 }
    "Error: Too many"        { puts "ERR_AUTH"; exit 1 }
    timeout                  { puts "ERR_TIMEOUT"; exit 1 }
    eof                      { puts "ERR_AUTH"; exit 1 }
}
EOF
)
    else
        EXPECT_SCRIPT=$(cat << EOF
log_user 1
set timeout $SSH_TIMEOUT

set pass \$env(_SW_PASS)

spawn ssh -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=10 \
          -o PreferredAuthentications=password \
          ${SWUSER}@${SWIP}

expect {
    "password:" { send "\$pass\r" }
    timeout     { puts "ERR_TIMEOUT"; exit 1 }
    eof         { puts "ERR_EOF";     exit 1 }
}

expect {
    -re {<[^>]+>}            {}
    "password:"              { puts "ERR_AUTH"; exit 1 }
    "Authentication failed"  { puts "ERR_AUTH"; exit 1 }
    "Permission denied"      { puts "ERR_AUTH"; exit 1 }
    "Error: Too many"        { puts "ERR_AUTH"; exit 1 }
    timeout                  { puts "ERR_TIMEOUT"; exit 1 }
    eof                      { puts "ERR_AUTH"; exit 1 }
}
EOF
)
    fi

    EXPECT_SCRIPT+=$(cat << 'EOF'

send "screen-length 0 temporary\r"
expect -re {<[^>]+>}

send "display current-configuration\r"
expect -re {<[^>]+>}

send "q\r"
expect eof
EOF
)

    EXPECT_OUT=$(expect <(echo "$EXPECT_SCRIPT") 2>&1)
    unset _SW_PASS

    # ---------- auth result ----------
    if echo "$EXPECT_OUT" | grep -q "ERR_AUTH"; then
        step_line "AUTH" "${RED}FAIL${RESET}" "${RED}(wrong password or user)${RESET}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${SWUSER}@${SWIP}  :  authentication failed")
        continue
    elif echo "$EXPECT_OUT" | grep -q "ERR_EOF\|Connection refused\|No route to host"; then
        step_line "AUTH" "${RED}FAIL${RESET}" "${RED}(connection refused or no route)${RESET}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${SWUSER}@${SWIP}  :  connection refused or no route")
        continue
    elif echo "$EXPECT_OUT" | grep -q "ERR_TIMEOUT"; then
        step_line "AUTH" "${RED}FAIL${RESET}" "${RED}(connection timed out)${RESET}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${SWUSER}@${SWIP}  :  SSH timed out")
        continue
    else
        AUTH_LABEL="using $(echo "$AUTH_MODE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        step_line "AUTH" "${GREEN}OK${RESET}" "${DIM}(${AUTH_LABEL})${RESET}"
    fi

    # ---------- fetch ----------
    SYSNAME=$(echo "$EXPECT_OUT" | grep -oP '<\K[^>]+' | head -1)
    [[ -z "$SYSNAME" ]] && SYSNAME="$SWIP"

    step_line "FETCH" "${GREEN}OK${RESET}" "${DIM}(Host: ${SYSNAME})${RESET}"

    # ---------- write ----------
    OUTFILE="${BACKUP_DIR}/${SYSNAME}_$(date +%Y%m%d_%H%M%S).cfg"
    CLEAN_OUT=$(echo "$EXPECT_OUT" | sed 's/\x1b\[[0-9;]*m//g; s/\r//' | sed -n '/^Info:/,$p')
    echo "$CLEAN_OUT" > "$OUTFILE"

    if grep -q "sysname" "$OUTFILE" 2>/dev/null; then
        FSIZE=$(filesize "$OUTFILE")
        step_line "WRITE" "${GREEN}OK${RESET}" "${OUTFILE##*/}  (${FSIZE})"
        SUCCESS=$((SUCCESS + 1))
    else
        step_line "WRITE" "${RED}FAIL${RESET}" "${RED}(invalid config — check ${OUTFILE})${RESET}"
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("${SWUSER}@${SWIP}  :  invalid config output")
    fi

done

# ---------- summary ----------
tlog ""
tlog "  ${SSEP}"
if [[ $FAILED -eq 0 ]]; then
    tlog "  RESULT  :  ${GREEN}${SUCCESS} succeeded${RESET}  ·  ${RED}${FAILED} failed${RESET}  ·  ${TOTAL} total"
else
    tlog "  RESULT  :  ${GREEN}${SUCCESS} succeeded${RESET}  ·  ${RED}${BOLD}${FAILED} failed${RESET}  ·  ${TOTAL} total"
fi
tlog "  ELAPSED :  $(elapsed)"
tlog "  OUTPUT  :  ${BACKUP_DIR}/"
tlog "  LOGFILE :  ${LOG_FILE}"

# ---------- failed list ----------
if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    tlog ""
    tlog "  FAILED LIST:"

    # find longest user@ip for column alignment
    MAX_LEN=0
    for entry in "${FAILED_LIST[@]}"; do
        UHOST=$(echo "$entry" | awk -F'  :  ' '{print $1}')
        [[ ${#UHOST} -gt $MAX_LEN ]] && MAX_LEN=${#UHOST}
    done

    for j in "${!FAILED_LIST[@]}"; do
        UHOST=$(echo  "${FAILED_LIST[$j]}" | awk -F'  :  ' '{print $1}')
        REASON=$(echo "${FAILED_LIST[$j]}" | awk -F'  :  ' '{print $2}')
        tlog "$(printf "    %d.  ${RED}%-${MAX_LEN}s${RESET}  :  %s" "$((j+1))" "$UHOST" "$REASON")"
    done
fi

tlog "  ${SSEP}"
tlog ""
