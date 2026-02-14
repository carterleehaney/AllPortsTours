#!/bin/sh
# Universal iptables network logging setup
# Compatible with: RHEL/CentOS, Debian, Ubuntu, Arch Linux
# Run with: sudo ./setup-iptables-logging.sh

set -e  # Exit on error

echo "=== iptables Network Logging Setup ==="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root or with sudo"
    exit 1
fi

echo "[1/5] Checking system type..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    echo "    Detected: $OS_NAME"
else
    echo "[!] Cannot determine OS type"
    exit 1
fi

echo ""
echo "[2/5] Checking if iptables is installed..."
if ! command -v iptables >/dev/null 2>&1; then
    echo "[!] iptables not found. Installing..."
    
    # Detect package manager and install
    if command -v yum >/dev/null 2>&1; then
        yum install -y iptables iptables-services
    elif command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y iptables iptables-persistent
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm iptables
    else
        echo "[!] Could not detect package manager. Please install iptables manually."
        exit 1
    fi
    echo "    iptables installed"
else
    echo "    iptables already installed"
fi

echo ""
echo "[3/5] Adding iptables logging rules..."

# Check if rules already exist to avoid duplicates
if iptables -L OUTPUT -n | grep -q "LOG.*NETOUT:"; then
    echo "    Outbound logging rule already exists, skipping..."
else
    iptables -I OUTPUT 1 -m state --state NEW -j LOG --log-prefix "NETOUT: " --log-level 4
    echo "    Added outbound connection logging"
fi

if iptables -L INPUT -n | grep -q "LOG.*NETIN:"; then
    echo "    Inbound logging rule already exists, skipping..."
else
    iptables -I INPUT 1 -m state --state NEW -j LOG --log-prefix "NETIN: " --log-level 4
    echo "    Added inbound connection logging"
fi

echo ""
echo "[4/5] Making rules persistent across reboots..."

# Detect OS and save rules appropriately
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    # Enable on boot (different methods for different versions)
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
        systemctl enable netfilter-persistent
        echo "    Saved with netfilter-persistent (Debian/Ubuntu)"
    elif [ -f /etc/network/if-pre-up.d/iptables ]; then
        # Older Debian/Ubuntu
        echo "#!/bin/sh" > /etc/network/if-pre-up.d/iptables
        echo "/sbin/iptables-restore < /etc/iptables/rules.v4" >> /etc/network/if-pre-up.d/iptables
        chmod +x /etc/network/if-pre-up.d/iptables
        echo "    Saved with if-pre-up script (Debian/Ubuntu)"
    else
        echo "    Rules saved to /etc/iptables/rules.v4"
        echo "    [!] Note: Auto-restore on boot may need manual configuration"
    fi
    
elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS
    if command -v systemctl >/dev/null 2>&1; then
        # CentOS 7+/RHEL 7+
        mkdir -p /etc/sysconfig
        iptables-save > /etc/sysconfig/iptables
        
        # Enable iptables service
        if systemctl list-unit-files | grep -q iptables.service; then
            systemctl enable iptables.service
            echo "    Saved with systemd (CentOS/RHEL)"
        else
            echo "    Rules saved to /etc/sysconfig/iptables"
        fi
    else
        # CentOS 6/RHEL 6
        service iptables save
        chkconfig iptables on
        echo "    Saved with service (CentOS/RHEL)"
    fi
    
elif [ -f /etc/arch-release ]; then
    # Arch Linux
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/iptables.rules
    systemctl enable iptables.service
    echo "    Saved with systemd (Arch Linux)"
    
else
    # Fallback for unknown systems
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo "    Rules saved to /etc/iptables/rules.v4"
    echo "    [!] Unknown system - may need manual configuration for auto-restore"
fi

echo ""
echo "[5/5] Verifying installation..."
echo ""
echo "Current iptables LOG rules:"
iptables -L INPUT -n -v --line-numbers | grep LOG || echo "    No INPUT LOG rules (unexpected!)"
iptables -L OUTPUT -n -v --line-numbers | grep LOG || echo "    No OUTPUT LOG rules (unexpected!)"

echo ""
echo "=== Installation Summary ==="
echo "✓ iptables logging rules added"
echo "✓ Rules configured to persist across reboots"
echo ""
echo "Network connection logs will appear in:"
if [ -f /etc/debian_version ]; then
    echo "  - /var/log/syslog (Ubuntu/Debian)"
    echo "  - /var/log/kern.log (Ubuntu/Debian)"
elif [ -f /etc/redhat-release ]; then
    echo "  - /var/log/messages (CentOS/RHEL)"
elif [ -f /etc/arch-release ]; then
    echo "  - journalctl -k (Arch Linux kernel logs)"
    echo "  - /var/log/journal/ (if persistent)"
fi
echo ""
echo "Log format examples:"
echo "  NETOUT: IN= OUT=eth0 SRC=192.168.1.102 DST=8.8.8.8 PROTO=TCP SPT=45678 DPT=443"
echo "  NETIN: IN=eth0 OUT= SRC=10.10.0.50 DST=192.168.1.105 PROTO=TCP SPT=52341 DPT=22"
echo ""
echo "To test, run: tail -f /var/log/syslog | grep 'NETIN:\\|NETOUT:'"
echo "(or 'journalctl -kf' on Arch)"
echo ""
echo "=== Setup Complete ==="
