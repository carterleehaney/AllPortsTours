#!/bin/bash

# ==========================================
# REMOTE BLUE TEAM WATCHDOG (Centralized)
# ==========================================
# Multi-distro compatible service monitor & recovery tool.
# Supports: Debian/Ubuntu, RHEL/CentOS/Fedora, Arch, Alpine (OpenRC),
#           and legacy SysVinit systems.
#
# Features:
#   - Detects init system on each remote host (systemd, OpenRC, SysVinit)
#   - Automatically unmasks masked services (systemd)
#   - Attempts restart of down services
#   - On failure, grabs last logs from:
#       1) systemctl status (if systemd)
#       2) journalctl      (if systemd + journald)
#       3) /var/log/syslog or /var/log/messages (last resort)
#
# Usage: ./Watchdog.sh -u <user> -p <password> [-f <hostfile>]
#
# Host file format (one per line):
#   <IP> <service1> <service2> ...
#
# Example:
#   ./Watchdog.sh -u root -p "changeme"
#   ./Watchdog.sh -u admin -p "password" -f hosts.txt
# ==========================================

# ---------------- CONFIGURATION ----------------
# Define your hosts and the services to check on them.
# Format: HOST_MAP["IP_ADDRESS"]="service1 service2 service3"

declare -A HOST_MAP

# EXAMPLE CONFIGURATION (Edit these IPs and Services!)
HOST_MAP["192.168.1.9"]="apache2 ssh"
HOST_MAP["192.168.1.10"]="mysql ssh cron"
HOST_MAP["192.168.1.2"]="apache2 ssh"

# Time between checks (in seconds)
SLEEP_INTERVAL=10
LOG_FILE="watchdog.log"

# -----------------------------------------------

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# -----------------------------------------------
# Install sshpass if missing
# -----------------------------------------------
if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}'sshpass' is not installed. Attempting to install...${NC}"

    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y sshpass
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y sshpass
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm sshpass
    elif [ -x "$(command -v apk)" ]; then
        sudo apk add sshpass
    elif [ -x "$(command -v zypper)" ]; then
        sudo zypper install -y sshpass
    elif [ -x "$(command -v emerge)" ]; then
        sudo emerge net-misc/sshpass
    else
        echo -e "${RED}Error: Could not find a package manager to install 'sshpass'.${NC}"
        echo "Please install it manually."
        exit 1
    fi

    # Verify installation
    if ! command -v sshpass &> /dev/null; then
         echo -e "${RED}Error: Failed to install 'sshpass'.${NC}"
         exit 1
    else
         echo -e "${GREEN}Successfully installed 'sshpass'.${NC}"
    fi
fi

# -----------------------------------------------
# Parse Flags
# -----------------------------------------------
USERNAME=""
PASSWORD=""
HOST_FILE=""

while getopts "u:p:f:" opt; do
  case $opt in
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    f) HOST_FILE="$OPTARG" ;;
    *) echo "Usage: $0 -u <username> -p <password> [-f <hostfile>]" ; exit 1 ;;
  esac
done

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    echo -e "${RED}Error: You must provide a username and password.${NC}"
    echo "Usage: $0 -u <user> -p <password> [-f <hostfile>]"
    exit 1
fi

# -----------------------------------------------
# Load hosts from file if provided
# -----------------------------------------------
if [[ -n "$HOST_FILE" ]]; then
    if [[ ! -f "$HOST_FILE" ]]; then
        echo -e "${RED}Error: Host file '$HOST_FILE' not found.${NC}"
        exit 1
    fi

    # Clear the default HOST_MAP when using a file
    unset HOST_MAP
    declare -A HOST_MAP

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue

        FILE_IP=$(echo "$line" | awk '{print $1}')
        FILE_SERVICES=$(echo "$line" | cut -d' ' -f2-)
        HOST_MAP["$FILE_IP"]="$FILE_SERVICES"
    done < "$HOST_FILE"

    echo -e "${GREEN}[*] Loaded ${#HOST_MAP[@]} host(s) from '$HOST_FILE'${NC}"
fi

echo -e "${BLUE}[*] Starting Remote Watchdog Network Monitor...${NC}"
echo -e "${BLUE}[*] User: $USERNAME ${NC}"
echo -e "${BLUE}[*] Hosts: ${#HOST_MAP[@]} ${NC}"
echo "----------------------------------------------------"

# -----------------------------------------------
# The remote script that runs on each host.
# This is designed to work across:
#   - systemd (Debian, Ubuntu, CentOS 7+, Fedora, Arch, RHEL 7+)
#   - OpenRC  (Alpine, Gentoo)
#   - SysVinit (older Debian, CentOS 6, etc.)
# -----------------------------------------------
build_remote_script() {
    local SERVICES="$1"
    local SAFE_PASS="$2"

    cat << 'REMOTE_HEREDOC'
#!/bin/bash
SERVICES_LIST="__SERVICES__"
SAFE_PASS="__PASS__"

# --- Detect init system ---
INIT_SYSTEM="unknown"

if command -v systemctl &> /dev/null && pidof systemd &> /dev/null; then
    INIT_SYSTEM="systemd"
elif command -v rc-service &> /dev/null; then
    INIT_SYSTEM="openrc"
elif command -v service &> /dev/null; then
    INIT_SYSTEM="sysvinit"
elif [ -f /etc/init.d/rc ]; then
    INIT_SYSTEM="sysvinit"
fi

echo "INIT|${INIT_SYSTEM}"

# --- Helper: Check if service is active ---
is_active() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd)
            systemctl is-active --quiet "$svc" 2>/dev/null
            ;;
        openrc)
            rc-service "$svc" status &>/dev/null
            ;;
        sysvinit)
            service "$svc" status &>/dev/null
            ;;
        *)
            # Last resort: check if process name is running
            pgrep -x "$svc" &>/dev/null
            ;;
    esac
}

# --- Helper: Check if service is masked (systemd only) ---
is_masked() {
    local svc="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        local state
        state=$(systemctl is-enabled "$svc" 2>/dev/null)
        if [ "$state" = "masked" ] || [ "$state" = "masked-runtime" ]; then
            return 0
        fi
    fi
    return 1
}

# --- Helper: Unmask a service (systemd only) ---
unmask_service() {
    local svc="$1"
    echo "$SAFE_PASS" | sudo -S systemctl unmask "$svc" 2>/dev/null
    # Also daemon-reload after unmasking to pick up the real unit
    echo "$SAFE_PASS" | sudo -S systemctl daemon-reload 2>/dev/null
}

# --- Helper: Start/restart a service ---
start_service() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd)
            echo "$SAFE_PASS" | sudo -S systemctl restart "$svc" 2>/dev/null
            ;;
        openrc)
            echo "$SAFE_PASS" | sudo -S rc-service "$svc" restart 2>/dev/null
            ;;
        sysvinit)
            echo "$SAFE_PASS" | sudo -S service "$svc" restart 2>/dev/null
            ;;
        *)
            # Attempt a generic restart via init.d
            if [ -x "/etc/init.d/$svc" ]; then
                echo "$SAFE_PASS" | sudo -S /etc/init.d/"$svc" restart 2>/dev/null
            fi
            ;;
    esac
}

# --- Helper: Enable a service (so it survives reboot) ---
enable_service() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd)
            echo "$SAFE_PASS" | sudo -S systemctl enable "$svc" 2>/dev/null
            ;;
        openrc)
            echo "$SAFE_PASS" | sudo -S rc-update add "$svc" default 2>/dev/null
            ;;
        sysvinit)
            if command -v update-rc.d &>/dev/null; then
                echo "$SAFE_PASS" | sudo -S update-rc.d "$svc" defaults 2>/dev/null
            elif command -v chkconfig &>/dev/null; then
                echo "$SAFE_PASS" | sudo -S chkconfig "$svc" on 2>/dev/null
            fi
            ;;
    esac
}

# --- Helper: Grab last resort logs ---
grab_logs() {
    local svc="$1"
    echo "LOG_START"

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        # systemctl status (quick view with recent log lines)
        echo "=== systemctl status $svc ==="
        echo "$SAFE_PASS" | sudo -S systemctl status "$svc" -n 30 --no-pager 2>/dev/null
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        echo "=== rc-service $svc status ==="
        rc-service "$svc" status 2>/dev/null
    elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
        echo "=== service $svc status ==="
        service "$svc" status 2>/dev/null
    fi

    echo "LOG_END"
}

# =============================================
# MAIN LOOP: Check each service
# =============================================
for SVC in $SERVICES_LIST; do

    # ---- Step 1: Check if active ----
    if is_active "$SVC"; then
        echo "OK|$SVC"
        continue
    fi

    # ---- Step 2: Check if masked (systemd only) ----
    if is_masked "$SVC"; then
        echo "MASKED|$SVC"
        unmask_service "$SVC"
        sleep 1

        # After unmasking, try to start
        start_service "$SVC"
        sleep 2

        if is_active "$SVC"; then
            echo "UNMASKED_RESTARTED|$SVC"
            enable_service "$SVC"
            continue
        else
            echo "UNMASKED_FAILED|$SVC"
            grab_logs "$SVC"
            continue
        fi
    fi

    # ---- Step 3: Service is down but not masked — try restart ----
    start_service "$SVC"
    sleep 2

    if is_active "$SVC"; then
        echo "RESTARTED|$SVC"
        continue
    fi

    # ---- Step 4: Restart failed — critical failure ----
    echo "FAILED|$SVC"
    grab_logs "$SVC"

done
REMOTE_HEREDOC
}

while true; do
    TIMESTAMP=$(date '+%H:%M:%S')
    echo -e "${CYAN}--- Scan at $TIMESTAMP ---${NC}"

    for IP in "${!HOST_MAP[@]}"; do
        SERVICES="${HOST_MAP[$IP]}"
        
        # Safe quote the password to prevent issues with special chars
        SAFE_PASS=$(printf '%q' "$PASSWORD")

        # Build the remote script with services and password substituted in
        REMOTE_SCRIPT=$(build_remote_script "$SERVICES" "$SAFE_PASS")
        REMOTE_SCRIPT="${REMOTE_SCRIPT//__SERVICES__/$SERVICES}"
        REMOTE_SCRIPT="${REMOTE_SCRIPT//__PASS__/$SAFE_PASS}"

        # Connect via SSH and run the check
        # -o StrictHostKeyChecking=no  prevents "Are you sure?" prompts
        # -o ConnectTimeout=5          prevents hanging if a box is down
        # -o UserKnownHostsFile=/dev/null  prevents host key conflicts
        OUTPUT=$(sshpass -p "$PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -q "$USERNAME@$IP" "$REMOTE_SCRIPT" 2>/dev/null)
        
        EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
            echo -e "${RED}[$IP] HOST DOWN or AUTH FAILED (exit code: $EXIT_CODE)${NC}"
            echo "[$TIMESTAMP] [$IP] CONNECTION FAILED (exit: $EXIT_CODE)" >> "$LOG_FILE"
        else
            # Process the output from the remote host
            echo -e "${YELLOW}[$IP]${NC}"
            READING_LOGS=false
            REMOTE_INIT=""

            while IFS= read -r line; do
                if [[ -z "$line" ]]; then continue; fi

                # Detect init system reported by remote host
                if [[ "$line" == INIT\|* ]]; then
                    REMOTE_INIT=$(echo "$line" | cut -d'|' -f2)
                    echo -e "   ${BLUE}Init System: ${REMOTE_INIT}${NC}"
                    continue
                fi
                
                # Check for log markers
                if [[ "$line" == "LOG_START" ]]; then
                    READING_LOGS=true
                    echo -e "${RED}   --- SERVICE LOGS ---${NC}"
                    continue
                elif [[ "$line" == "LOG_END" ]]; then
                    READING_LOGS=false
                    echo -e "${RED}   --- END LOGS -------${NC}"
                    continue
                fi

                if [[ "$READING_LOGS" == "true" ]]; then
                    # Print log lines (indented)
                    echo -e "      $line"
                else
                    # Normal Status Parsing
                    STATUS=$(echo "$line" | cut -d'|' -f1)
                    SVC_NAME=$(echo "$line" | cut -d'|' -f2)

                    if [[ "$STATUS" == "OK" ]]; then
                        echo -e "   $SVC_NAME: ${GREEN}ACTIVE${NC}"

                    elif [[ "$STATUS" == "MASKED" ]]; then
                        echo -e "   $SVC_NAME: ${MAGENTA}MASKED (attempting unmask)${NC}"
                        echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: MASKED" >> "$LOG_FILE"

                    elif [[ "$STATUS" == "UNMASKED_RESTARTED" ]]; then
                        echo -e "   $SVC_NAME: ${YELLOW}WAS MASKED -> UNMASKED & RESTARTED${NC}"
                        echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: UNMASKED_RESTARTED" >> "$LOG_FILE"

                    elif [[ "$STATUS" == "UNMASKED_FAILED" ]]; then
                        echo -e "   $SVC_NAME: ${RED}UNMASKED BUT FAILED TO START${NC}"
                        echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: UNMASKED_FAILED" >> "$LOG_FILE"

                    elif [[ "$STATUS" == "RESTARTED" ]]; then
                        echo -e "   $SVC_NAME: ${YELLOW}WAS DOWN -> RESTARTED${NC}"
                        echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: RESTARTED" >> "$LOG_FILE"

                    elif [[ "$STATUS" == "FAILED" ]]; then
                        echo -e "   $SVC_NAME: ${RED}CRITICAL FAILURE (Could not start)${NC}"
                        echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: FAILED" >> "$LOG_FILE"
                    fi
                fi
            done <<< "$OUTPUT"
        fi
    done

    echo ""
    sleep $SLEEP_INTERVAL
done