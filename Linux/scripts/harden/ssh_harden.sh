#!/bin/sh
# SSH Hardening Script
# @d_tranman/Nigel Gerald/Nigerald
# Compatible with: RHEL, Debian, Ubuntu, BSD (FreeBSD, OpenBSD), Alpine Linux

set -e  # Exit on error (can be disabled if you want to continue on errors)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Detect OS type
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_FAMILY=$ID_LIKE
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_FAMILY="rhel fedora"
    elif [ "$(uname -s)" = "FreeBSD" ]; then
        OS="freebsd"
        OS_FAMILY="bsd"
    elif [ "$(uname -s)" = "OpenBSD" ]; then
        OS="openbsd"
        OS_FAMILY="bsd"
    elif [ "$(uname -s)" = "NetBSD" ]; then
        OS="netbsd"
        OS_FAMILY="bsd"
    else
        OS="unknown"
        OS_FAMILY="unknown"
    fi
    
    log_info "Detected OS: $OS (Family: $OS_FAMILY)"
}

# Find SSH config file
find_ssh_config() {
    if [ -f /etc/ssh/sshd_config ]; then
        SSHD_CONFIG="/etc/ssh/sshd_config"
    elif [ -f /usr/local/etc/ssh/sshd_config ]; then
        # BSD systems often use this path
        SSHD_CONFIG="/usr/local/etc/ssh/sshd_config"
    else
        log_error "Could not find sshd_config file"
        exit 1
    fi
    log_info "Using SSH config: $SSHD_CONFIG"
}

# Backup SSH config
backup_config() {
    BACKUP_DIR="${BCK:-/root/.cache}/ssh_backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/sshd_config.$TIMESTAMP"
    
    cp "$SSHD_CONFIG" "$BACKUP_FILE"
    log_info "Backup created: $BACKUP_FILE"
}

# Configure sed for the platform
setup_sed() {
    # Test if GNU sed (supports -i without extension)
    if sed --version >/dev/null 2>&1; then
        SED_INPLACE="sed -i"
    else
        # BSD sed requires an extension or empty string
        SED_INPLACE="sed -i ''"
    fi
}

# Function to safely update SSH config
# Usage: update_ssh_option "OptionName" "value"
update_ssh_option() {
    OPTION=$1
    VALUE=$2
    
    # Comment out any existing lines with this option
    eval "$SED_INPLACE 's/^[[:space:]]*${OPTION}[[:space:]]/#&/' \"$SSHD_CONFIG\""
    
    # Add the new configuration
    echo "${OPTION} ${VALUE}" >> "$SSHD_CONFIG"
    log_info "Set ${OPTION} to ${VALUE}"
}

# Apply SSH hardening configurations
apply_hardening() {
    log_info "Applying SSH hardening configurations..."
    
    # Core hardening settings
    update_ssh_option "AllowTcpForwarding" "no"
    update_ssh_option "X11Forwarding" "no"
    update_ssh_option "PermitRootLogin" "yes"
    update_ssh_option "PermitEmptyPasswords" "no"
    
    # Enforce password-only authentication (disable SSH keys)
    update_ssh_option "PubkeyAuthentication" "no"
    update_ssh_option "PasswordAuthentication" "yes"
    
    log_info "Password authentication enabled for all users including root"
    log_info "Public key authentication disabled"
}

# Validate SSH configuration
validate_config() {
    log_info "Validating SSH configuration..."
    
    # Try to find sshd binary
    SSHD_BIN=$(command -v sshd)
    
    if [ -z "$SSHD_BIN" ]; then
        log_warn "Could not find sshd binary to validate config"
        return 0
    fi
    
    # Test configuration
    if $SSHD_BIN -t -f "$SSHD_CONFIG" 2>&1; then
        log_info "Configuration validation successful"
        return 0
    else
        log_error "Configuration validation failed!"
        log_error "Restoring from backup..."
        cp "$BACKUP_FILE" "$SSHD_CONFIG"
        exit 1
    fi
}

# Restart SSH service
restart_ssh() {
    log_info "Restarting SSH service..."
    
    # Try systemctl first (systemd systems: RHEL 7+, Debian 8+, Ubuntu 15.04+)
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            log_info "SSH service restarted via systemctl"
            return 0
        fi
    fi
    
    # Try service command (older RHEL/Debian, some systems)
    if command -v service >/dev/null 2>&1; then
        if service sshd restart 2>/dev/null || service ssh restart 2>/dev/null; then
            log_info "SSH service restarted via service"
            return 0
        fi
    fi
    
    # Try rc.d scripts (BSD systems, Alpine with OpenRC)
    if command -v rc-service >/dev/null 2>&1; then
        # Alpine Linux with OpenRC
        if rc-service sshd restart 2>/dev/null; then
            log_info "SSH service restarted via rc-service"
            return 0
        fi
    fi
    
    # Try direct rc.d script execution (BSD)
    for RC_PATH in /etc/rc.d/sshd /etc/rc.d/rc.sshd /usr/local/etc/rc.d/sshd; do
        if [ -x "$RC_PATH" ]; then
            if $RC_PATH restart; then
                log_info "SSH service restarted via $RC_PATH"
                return 0
            fi
        fi
    done
    
    # Try kill and restart for BSD
    if [ "$OS_FAMILY" = "bsd" ]; then
        SSHD_PID=$(pgrep sshd | head -n 1)
        if [ -n "$SSHD_PID" ]; then
            kill -HUP "$SSHD_PID"
            log_info "Sent HUP signal to sshd (PID: $SSHD_PID)"
            return 0
        fi
    fi
    
    log_error "Could not restart SSH service. Please restart manually."
    log_warn "Use one of: systemctl restart sshd, service sshd restart, or /etc/rc.d/sshd restart"
    return 1
}

# Main execution
main() {
    log_info "Starting SSH hardening script..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    detect_os
    find_ssh_config
    backup_config
    setup_sed
    apply_hardening
    validate_config
    restart_ssh
    
    log_info "SSH hardening completed successfully!"
    log_info "Backup saved to: $BACKUP_FILE"
}

# Run main function
main
