#!/bin/bash

# ADDITIONS 
# Be able to input file with "<IP> <service1> <service2> ... "

# ==========================================
# REMOTE BLUE TEAM WATCHDOG (Centralized)
# ==========================================
# Usage: ./remote_watchdog.sh -u <user> -p <password>
# Example: ./remote_watchdog.sh -u root -p "changeme"

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
NC='\033[0m'

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: 'sshpass' is not installed.${NC}"
    echo "Please run: sudo apt install sshpass"
    exit 1
fi

# Parse Flags
USERNAME=""
PASSWORD=""

while getopts "u:p:" opt; do
  case $opt in
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    *) echo "Usage: $0 -u <username> -p <password>" ; exit 1 ;;
  esac
done

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    echo -e "${RED}Error: You must provide a username and password.${NC}"
    echo "Usage: $0 -u <user> -p <password>"
    exit 1
fi

echo -e "${BLUE}[*] Starting Remote Watchdog Network Monitor...${NC}"
echo -e "${BLUE}[*] User: $USERNAME ${NC}"
echo "----------------------------------------------------"

while true; do
    TIMESTAMP=$(date '+%H:%M:%S')
    echo -e "${CYAN}--- Scan at $TIMESTAMP ---${NC}"

    for IP in "${!HOST_MAP[@]}"; do
        SERVICES="${HOST_MAP[$IP]}"
        
        # Safe quote the password to prevent issues with special chars
        SAFE_PASS=$(printf '%q' "$PASSWORD")

        # We build a small script to run on the remote host
        # UPDATED: Now pipes password into sudo -S to bypass prompt
        REMOTE_SCRIPT="
            for SVC in $SERVICES; do
                if systemctl is-active --quiet \$SVC; then
                    echo \"OK|\$SVC\"
                else
                    # Try to start it using sudo -S (reading password from echo)
                    # 2>/dev/null hides the 'password:' prompt text from output
                    echo $SAFE_PASS | sudo -S systemctl start \$SVC 2>/dev/null
                    
                    # Give the service a moment to actually start up
                    sleep 2
                    
                    if systemctl is-active --quiet \$SVC; then
                        echo \"RESTARTED|\$SVC\"
                    else
                        echo \"FAILED|\$SVC\"
                    fi
                fi
            done
        "

        # Connect via SSH and run the check
        # -o StrictHostKeyChecking=no prevents "Are you sure?" prompts
        # -o ConnectTimeout=3 prevents hanging if a box is down
        OUTPUT=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -q "$USERNAME@$IP" "$REMOTE_SCRIPT" 2>/dev/null)
        
        EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
            echo -e "${RED}[$IP] HOST DOWN or AUTH FAILED${NC}"
        else
            # Process the output from the remote host
            echo -e "${YELLOW}[$IP]${NC}"
            while IFS= read -r line; do
                if [[ -z "$line" ]]; then continue; fi
                
                STATUS=$(echo "$line" | cut -d'|' -f1)
                SVC_NAME=$(echo "$line" | cut -d'|' -f2)

                if [[ "$STATUS" == "OK" ]]; then
                    echo -e "   $SVC_NAME: ${GREEN}ACTIVE${NC}"
                elif [[ "$STATUS" == "RESTARTED" ]]; then
                    echo -e "   $SVC_NAME: ${YELLOW}WAS DOWN -> RESTARTED${NC}"
                    echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: RESTARTED" >> "$LOG_FILE"
                elif [[ "$STATUS" == "FAILED" ]]; then
                    echo -e "   $SVC_NAME: ${RED}CRITICAL FAILURE (Could not start)${NC}"
                    echo "[$TIMESTAMP] [$IP] Service: $SVC_NAME - Status: FAILED" >> "$LOG_FILE"
                fi
            done <<< "$OUTPUT"
        fi
    done

    echo ""
    sleep $SLEEP_INTERVAL
done