#!/bin/bash
# ==========================================================
# Service Discovery Tool for Watchdog.sh
# ==========================================================
# This script detects running network services on the current machine
# and outputs a configuration based on the Watchdog.sh format.
# 
# Supported OS: Debian/Ubuntu, RHEL/CentOS, FreeBSD, OpenBSD
# Required Tools: 'ss' OR 'netstat' OR 'sockstat' (BSD)
#
# PROCESS-TO-SERVICE MAPPING:
# ---------------------------
# Many processes have different names than their systemd service files.
# For example: cupsd (process) -> cups.service (systemd)
#
# This script automatically maps common process names to their correct
# service names. To add custom mappings, edit the KNOWN_MAPPINGS array
# in the map_to_service() function (around line 50).
#
# The script uses multiple strategies to find the correct service name:
#   1. Check known mappings table
#   2. Try exact process name
#   3. Try removing 'd' suffix (cupsd -> cups)
#   4. Try adding 'd' suffix (ssh -> sshd)
#   5. Query systemd directly
# ==========================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
    elif [ -f /etc/redhat-release ]; then
        OS_NAME="Red Hat/CentOS"
    elif [ "$(uname)" == "FreeBSD" ]; then
        OS_NAME="FreeBSD"
    elif [ "$(uname)" == "OpenBSD" ]; then
        OS_NAME="OpenBSD"
    else
        OS_NAME=$(uname)
    fi
}

get_local_ip() {
    # Try hostname -I (Linux) or ifconfig (BSD/Linux)
    if command -v hostname &> /dev/null && hostname -I &> /dev/null; then
        hostname -I | awk '{print $1}'
    elif command -v ifconfig &> /dev/null; then
        # Grab first non-loopback inet address
        ifconfig | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | head -n 1 | awk '{print $2}'
    else
        echo "IP_ADDRESS"
    fi
}

# -----------------------------------------------
# Map process names to systemd service names
# -----------------------------------------------
# Many processes have different names than their service files
# This function attempts to find the correct service name
map_to_service() {
    local proc="$1"
    local service_name=""
    
    # Common process -> service mappings
    # Format: "processname:servicename"
    declare -A KNOWN_MAPPINGS=(
        ["cupsd"]="cups"
        ["sshd"]="ssh"
        ["httpd"]="apache2"
        ["mysqld"]="mysql"
        ["postgres"]="postgresql"
        ["named"]="bind9"
        ["ntpd"]="ntp"
        ["chronyd"]="chrony"
        ["rsyslogd"]="rsyslog"
        ["systemd-resolved"]="systemd-resolved"
        ["systemd-networkd"]="systemd-networkd"
        ["systemd-timesyncd"]="systemd-timesyncd"
        ["NetworkManager"]="NetworkManager"
        ["dnsmasq"]="dnsmasq"
        ["avahi-daemon"]="avahi-daemon"
        ["bluetoothd"]="bluetooth"
        ["smbd"]="smbd"
        ["nmbd"]="nmbd"
        ["winbindd"]="winbind"
        ["dovecot"]="dovecot"
        ["master"]="postfix"
        ["nginx"]="nginx"
        ["php-fpm"]="php-fpm"
        ["redis-server"]="redis"
        ["mongod"]="mongod"
    )
    
    # Check if we have a known mapping
    if [[ -n "${KNOWN_MAPPINGS[$proc]}" ]]; then
        service_name="${KNOWN_MAPPINGS[$proc]}"
        # Verify it exists in systemd (try multiple methods)
        if systemctl list-unit-files "${service_name}.service" &> /dev/null || \
           systemctl status "${service_name}" &> /dev/null 2>&1 || \
           systemctl is-active "${service_name}" &> /dev/null 2>&1; then
            echo "$service_name"
            return 0
        fi
    fi
    
    # Strategy 1: Try exact process name as service
    if systemctl list-unit-files "${proc}.service" &> /dev/null; then
        echo "$proc"
        return 0
    fi
    
    # Strategy 2: Try removing 'd' suffix (e.g., cupsd -> cups)
    if [[ "$proc" == *d ]]; then
        local without_d="${proc%d}"
        if systemctl list-unit-files "${without_d}.service" &> /dev/null || \
           systemctl status "${without_d}" &> /dev/null 2>&1; then
            echo "$without_d"
            return 0
        fi
    fi
    
    # Strategy 3: Try adding 'd' suffix (e.g., ssh -> sshd)
    if systemctl list-unit-files "${proc}d.service" &> /dev/null; then
        echo "${proc}d"
        return 0
    fi
    
    # Strategy 4: Check if systemd knows about it via is-active
    # (handles cases where service file exists but isn't in list-unit-files)
    if systemctl is-active "$proc" &>/dev/null 2>&1 || \
       systemctl status "$proc" &>/dev/null 2>&1; then
        echo "$proc"
        return 0
    fi
    
    # Fallback: Return original process name
    echo "$proc"
    return 1
}

get_services() {
    FOUND_SERVICES=""

    # ------------------- LINUX LOGIC -------------------
    if [[ "$(uname)" == "Linux" ]]; then
        # Check for ss
        if command -v ss &> /dev/null; then
            # Run ss -tulpn (requires sudo for process names)
            # Output format example: users:(("sshd",pid=123,fd=3))
            if [ "$EUID" -ne 0 ]; then
                echo "Warning: Not running as root. Process names might be hidden." >&2
                RAW_DATA=$(ss -tulpn)
            else
                RAW_DATA=$(ss -tulpn)
            fi
            
            # Extract ONLY the process names (first quoted string before ",pid=")
            # This regex captures the process name and stops before the comma
            PROCS=$(echo "$RAW_DATA" | grep LISTEN | grep -oP '\(\("?\K[^",]+' | sort | uniq)
        
        # Fallback to netstat
        elif command -v netstat &> /dev/null; then
            if [ "$EUID" -ne 0 ]; then
                 echo "Warning: Not running as root. Process names might be hidden." >&2
            fi
            # Output format: tcp ... 1234/sshd
            RAW_DATA=$(netstat -tulpn 2>/dev/null)
            PROCS=$(echo "$RAW_DATA" | grep LISTEN | awk '{print $7}' | cut -d'/' -f2 | sort | uniq)
        else
            echo "Error: Neither 'ss' nor 'netstat' found on Linux." >&2
            return
        fi

        # Map processes to Systemd Services if possible
        for proc in $PROCS; do
            # Clean up empty lines and filter out garbage
            if [[ -z "$proc" ]]; then continue; fi
            # Skip entries that look like PIDs or file descriptors
            if [[ "$proc" =~ ^[0-9]+$ ]] || [[ "$proc" =~ pid= ]] || [[ "$proc" =~ fd= ]]; then
                continue
            fi
            
            # Use the mapping function to get the correct service name
            if command -v systemctl &> /dev/null; then
                mapped_service=$(map_to_service "$proc")
                FOUND_SERVICES="$FOUND_SERVICES $mapped_service"
            else
                # No systemd, just use process name
                FOUND_SERVICES="$FOUND_SERVICES $proc"
            fi
        done

    # ------------------- BSD LOGIC -------------------
    elif [[ "$(uname)" == *"BSD"* ]]; then
        # Use sockstat (FreeBSD/OpenBSD standard)
        if command -v sockstat &> /dev/null; then
            # sockstat -4l output: USER COMMAND PID FD ...
            # We want column 2 (COMMAND)
            PROCS=$(sockstat -4l | grep -v "COMMAND" | awk '{print $2}' | sort | uniq)
            FOUND_SERVICES=$(echo "$PROCS" | tr '\n' ' ')
        
        # Fallback to netstat
        elif command -v netstat &> /dev/null; then
            # netstat on BSD is tricky for process names without flags like -p (not avail on all)
            # OpenBSD netstat -p protocol, not process. 
            echo "Warning: Identifying processes via netstat on BSD is limited without 'sockstat'. install sockstat if possible." >&2
        fi
    fi

    echo "$FOUND_SERVICES" | xargs # trim whitespace
}

# Run
detect_os
MY_IP=$(get_local_ip)
SERVICES=$(get_services)

# Sort services alphabetically for cleaner output
SERVICES_SORTED=$(echo "$SERVICES" | tr ' ' '\n' | sort | uniq | tr '\n' ' ' | xargs)

# Get hostname
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

echo "============================================="
echo "WATCHDOG CONFIG GENERATOR"
echo "============================================="
echo "Hostname:         $HOSTNAME"
echo "Operating System: $OS_NAME"
echo "HOST_MAP[\"$MY_IP\"]=\"$SERVICES_SORTED\""
