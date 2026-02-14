#!/bin/sh
# Splunk Installer (Forwarder + Indexer)
# CraniacCombo CCDC | Merged from MSU-BlueScripts + TTU CCDC
#
# Usage (CLI flags, like MSU):
#   ./splunk.sh -f <INDEXER_IP> -p <PASSWORD>     # Install forwarder
#   ./splunk.sh -i -p <PASSWORD>                   # Install indexer
#   ./splunk.sh -h                                  # Show help
#
# Usage (env vars, for Coordinate-Meow):
#   coordinate-kali -t <targets> -u root -p <pass> \
#     --env "INDEXER=10.0.0.5;PASS=SplunkPass" scripts/logging/splunk.sh
#   coordinate-kali -t <indexer> -u root -p <pass> \
#     --env "MODE=indexer;PASS=SplunkPass" scripts/logging/splunk.sh
#
# Flags override env vars. If no flags are given, env vars are used.

###################### GLOBALS #########################
MODE="${MODE:-}"
INDEXER="${INDEXER:-}"
PASS="${PASS:-}"
SPLUNK_HOME=""
Receiver_Port="${PORT:-9997}"
PACKAGE="${PACKAGE:-auto}"
GITHUB_URL="${GITHUB_URL:-https://raw.githubusercontent.com/Jmilton42/SOC-scripts/main/Linux/Coordinate-Meow/Linux/scripts/logging}"
LOCAL_FOLDER="${LOCAL_FOLDER:-}"
INSTALL_AUDITD="${INSTALL_AUDITD:-true}"
INSTALL_SNOOPY="${INSTALL_SNOOPY:-true}"
INSTALL_SYSMON="${INSTALL_SYSMON:-true}"
INSTALL_SURICATA="${INSTALL_SURICATA:-true}"
INSTALL_IPTABLES_LOGGING="${INSTALL_IPTABLES_LOGGING:-true}"
INSTALL_C2_DETECTION="${INSTALL_C2_DETECTION:-true}"
FIREWALL_IP="${FIREWALL_IP:-}"
SPLUNK_ONLY="${SPLUNK_ONLY:-false}"
OG_SPLUNK_PASSWORD="${OG_SPLUNK_PASSWORD:-changeme}"
SPLUNK_USERNAME="${SPLUNK_USERNAME:-admin}"
BACKUP_DIR="${BACKUP_DIR:-/root/.cache/splunk}"
INDEXES="system web network windows misc snoopy ossec dns"
PM=""

# Auto-accept Splunk license for all splunk start/restart commands
export SPLUNK_START_ARGS="--accept-license --answer-yes --no-prompt"

# Forwarder URLs - 10.2.0 (primary), 9.4.0 (fallback), 9.2.5 (legacy for older glibc)
fwd_deb="https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.deb"
fwd_rpm="https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65.x86_64.rpm"
fwd_tgz="https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.tgz"
old_fwd_deb="https://download.splunk.com/products/universalforwarder/releases/9.4.0/linux/splunkforwarder-9.4.0-6b4ebe426ca6-linux-amd64.deb"
old_fwd_rpm="https://download.splunk.com/products/universalforwarder/releases/9.4.0/linux/splunkforwarder-9.4.0-6b4ebe426ca6.x86_64.rpm"
old_fwd_tgz="https://download.splunk.com/products/universalforwarder/releases/9.4.0/linux/splunkforwarder-9.4.0-6b4ebe426ca6-Linux-x86_64.tgz"
legacy_fwd_deb="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba-linux-2.6-amd64.deb"
legacy_fwd_rpm="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba.x86_64.rpm"
legacy_fwd_tgz="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba-Linux-x86_64.tgz"
arm_deb="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba-Linux-armv8.deb"
arm_rpm="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba.aarch64.rpm"
arm_tgz="https://download.splunk.com/products/universalforwarder/releases/9.2.5/linux/splunkforwarder-9.2.5-7bfc9a4ed6ba-Linux-armv8.tgz"
intel_macos_tgz="https://download.splunk.com/products/universalforwarder/releases/10.2.0/osx/splunkforwarder-10.2.0-d749cb17ea65-darwin-intel.tgz"
m1_macos_tgz="https://download.splunk.com/products/universalforwarder/releases/10.2.0/osx/splunkforwarder-10.2.0-d749cb17ea65-darwin-universal2.tgz"
free13_tgz="https://download.splunk.com/products/universalforwarder/releases/10.2.0/freebsd/splunkforwarder-10.2.0-11d9b4866399-freebsd13-amd64.tgz"
free14_tgz="https://download.splunk.com/products/universalforwarder/releases/10.2.0/freebsd/splunkforwarder-10.2.0-11d9b4866399-freebsd14-amd64.tgz"

# Indexer URLs - Splunk Enterprise 10.2.0 (primary), 9.4.0 (fallback), 9.2.5 (legacy)
idx_deb="https://download.splunk.com/products/splunk/releases/10.2.0/linux/splunk-10.2.0-d749cb17ea65-linux-amd64.deb"
idx_rpm="https://download.splunk.com/products/splunk/releases/10.2.0/linux/splunk-10.2.0-d749cb17ea65.x86_64.rpm"
idx_tgz="https://download.splunk.com/products/splunk/releases/10.2.0/linux/splunk-10.2.0-d749cb17ea65-linux-amd64.tgz"
old_idx_deb="https://download.splunk.com/products/splunk/releases/9.4.0/linux/splunk-9.4.0-6b4ebe426ca6-linux-amd64.deb"
old_idx_rpm="https://download.splunk.com/products/splunk/releases/9.4.0/linux/splunk-9.4.0-6b4ebe426ca6.x86_64.rpm"
old_idx_tgz="https://download.splunk.com/products/splunk/releases/9.4.0/linux/splunk-9.4.0-6b4ebe426ca6-Linux-x86_64.tgz"

# Status tracking
AUDITD_SUCCESSFUL=false
SNOOPY_SUCCESSFUL=false
SYSMON_SUCCESSFUL=false
SURICATA_SUCCESSFUL=false
IPTABLES_LOGGING_SUCCESSFUL=false
C2_DETECTION_SUCCESSFUL=false
FIREWALL_SYSLOG_SUCCESSFUL=false

# Colors
GREEN=''
YELLOW=''
BLUE=''
RED=''
NC=''
if [ -n "$COLOR" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
fi
########################################################

###################### HELPERS #########################
info() {
    echo "${BLUE}[*]${NC} $1"
}

error() {
    echo "${RED}[X] ERROR:${NC} $1"
}

banner() {
    echo ""
    echo "${YELLOW}#######################################${NC}"
    echo "${YELLOW}#${NC}   $1"
    echo "${YELLOW}#######################################${NC}"
    echo ""
}

download() {
    url="$1"
    output="$2"
    
    # If LOCAL_FOLDER is set, try to copy from local path first
    if [ -n "$LOCAL_FOLDER" ]; then
        # Extract relative path from URL (everything after GITHUB_URL base)
        local_file="$LOCAL_FOLDER/$(basename "$url")"
        
        # Also try to match subdirectory structure (e.g., splunk-apps/file.tgz)
        url_path=$(echo "$url" | sed "s|.*/scripts/logging/||")
        if [ -f "$LOCAL_FOLDER/$url_path" ]; then
            local_file="$LOCAL_FOLDER/$url_path"
        fi
        
        if [ -f "$local_file" ]; then
            info "Copying from local: $local_file"
            cp "$local_file" "$output"
            if [ -f "$output" ]; then
                return 0
            fi
        fi
    fi
    
    # Fall back to downloading from URL
    info "Downloading: $url"
    wget -O "$output" --no-check-certificate -q "$url" 2>/dev/null || \
        curl -L -o "$output" -s -k "$url" 2>/dev/null || \
        fetch -o "$output" "$url" 2>/dev/null

    # Validate download — file must exist
    if [ ! -f "$output" ]; then
        error "Download failed: file not created"
        return 1
    fi
    
    file_size=$(wc -c < "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo 0)
    # Default min size is 1024 bytes unless overridden by 3rd arg
    min_size="${3:-1024}"
    
    if [ "$file_size" -lt "$min_size" ] 2>/dev/null; then
        error "Download failed: file too small (${file_size} bytes) — likely a 404 or network error"
        rm -f "$output"
        return 1
    fi
}

print_usage() {
    echo "Splunk Installer (Forwarder + Indexer) - CraniacCombo CCDC"
    echo ""
    echo "Usage:"
    echo "  ./splunk.sh -f <INDEXER_IP> -p <PASSWORD> [flags]   Install forwarder"
    echo "  ./splunk.sh -i -p <PASSWORD> [flags]                Install indexer"
    echo "  ./splunk.sh -h                                       Show this help"
    echo ""
    echo "Flags:"
    echo "  -f <ip>       Install forwarder, forward to indexer at <ip>"
    echo "  -i            Install indexer (Splunk Enterprise)"
    echo "  -p <pass>     Splunk password (required)"
    echo "  -t <type>     Package type: auto, deb, rpm, tgz, old_deb, old_rpm,"
    echo "                old_tgz, arm_deb, arm_rpm, arm_tgz (default: auto)"
    echo "  -S            Splunk only (skip auditd, snoopy, sysmon, iptables)"
    echo "  -F <ip>       Receive firewall syslog from <ip> via rsyslog (indexer)"
    echo "  -C            Skip C2 detection app install (indexer)"
    echo "  -I            Skip iptables logging setup"
    echo "  -g <url>      Override GitHub URL for downloads"
    echo "  -l <path>     Local folder path for offline install (copies instead of downloads)"
    echo "  -h            Show this help message"
    echo ""
    echo "Environment variables (for Coordinate-Meow, flags override these):"
    echo "  INDEXER        Indexer IP (equivalent to -f)"
    echo "  PASS           Splunk password (equivalent to -p)"
    echo "  MODE           'indexer' or 'forwarder' (equivalent to -i / -f)"
    echo "  FIREWALL_IP    Firewall IP for syslog (equivalent to -F)"
    echo "  PACKAGE        Package type (equivalent to -t)"
    echo "  SPLUNK_ONLY    'true' to skip additional logging (equivalent to -S)"
    echo "  LOCAL_FOLDER   Path to local logging folder for offline install (equivalent to -l)"
    echo "  COLOR          Set to enable colored output"
    echo ""
    echo "Examples:"
    echo "  ./splunk.sh -f 10.0.0.5 -p SplunkPass"
    echo "  ./splunk.sh -i -p SplunkPass"
    echo "  ./splunk.sh -i -p SplunkPass -F 10.0.0.1"
    echo "  ./splunk.sh -f 10.0.0.5 -p SplunkPass -l /tmp/logging"
    echo "  INDEXER=10.0.0.5 PASS=Secret ./splunk.sh"
    echo "  LOCAL_FOLDER=/opt/logging MODE=indexer PASS=Secret ./splunk.sh"
}
########################################################

###################### FLAG PARSING ####################
SKIP_C2=false
SKIP_IPTABLES=false

while getopts "hf:ip:t:SF:CIg:l:" opt; do
    case $opt in
        h)
            print_usage
            exit 0
            ;;
        f)
            MODE="forwarder"
            INDEXER="$OPTARG"
            ;;
        i)
            MODE="indexer"
            ;;
        p)
            PASS="$OPTARG"
            ;;
        t)
            PACKAGE="$OPTARG"
            ;;
        S)
            SPLUNK_ONLY="true"
            ;;
        F)
            FIREWALL_IP="$OPTARG"
            ;;
        C)
            SKIP_C2=true
            ;;
        I)
            SKIP_IPTABLES=true
            ;;
        g)
            GITHUB_URL="$OPTARG"
            ;;
        l)
            LOCAL_FOLDER="$OPTARG"
            ;;
        \?)
            error "Invalid option: -$OPTARG"
            print_usage
            exit 1
            ;;
        :)
            error "Option -$OPTARG requires an argument (-h for help)"
            exit 1
            ;;
    esac
done

# Apply skip flags
if [ "$SKIP_C2" = "true" ]; then
    INSTALL_C2_DETECTION="false"
fi
if [ "$SKIP_IPTABLES" = "true" ]; then
    INSTALL_IPTABLES_LOGGING="false"
fi

# Resolve MODE from env vars if not set by flags
if [ -z "$MODE" ]; then
    if [ -n "$INDEXER" ]; then
        MODE="forwarder"
    fi
fi

# Default to showing help if nothing is set
if [ -z "$MODE" ]; then
    error "No mode specified. Use -f <ip> for forwarder or -i for indexer."
    echo ""
    print_usage
    exit 1
fi

# Validate password
if [ -z "$PASS" ]; then
    error "Password required. Use -p <password> or set PASS env var."
    exit 1
fi

# Validate indexer IP for forwarder mode
if [ "$MODE" = "forwarder" ]; then
    if [ -z "$INDEXER" ]; then
        error "Forwarder mode requires indexer IP. Use -f <ip> or set INDEXER env var."
        exit 1
    fi
fi

# Set SPLUNK_HOME based on mode
if [ "$MODE" = "indexer" ]; then
    SPLUNK_HOME="/opt/splunk"
else
    SPLUNK_HOME="/opt/splunkforwarder"
fi

# Resolve SCRIPT_DIR for config file lookups
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
########################################################

#################### OS DETECTION ######################
autodetect_os() {
    banner "Detecting OS and package manager"

    OS_TYPE="linux"
    OS_ARCH="$(uname -m)"

    if command -v apt-get >/dev/null 2>&1; then
        PM="apt-get"
        info "Detected apt-get (Debian/Ubuntu)"
        sudo apt-get update -qq 2>/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        PM="dnf"
        info "Detected dnf (Fedora/RHEL 8+)"
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
        info "Detected yum (RHEL/CentOS)"
    elif command -v zypper >/dev/null 2>&1; then
        PM="zypper"
        info "Detected zypper (OpenSUSE)"
    elif command -v pacman >/dev/null 2>&1; then
        PM="pacman"
        info "Detected pacman (Arch Linux)"
    elif command -v apk >/dev/null 2>&1; then
        PM="apk"
        info "Detected apk (Alpine Linux)"
    elif command -v pkg >/dev/null 2>&1; then
        PM="pkg"
        OS_TYPE="freebsd"
        FREEBSD_MAJOR="$(uname -r | cut -d. -f1)"
        info "Detected pkg (FreeBSD $FREEBSD_MAJOR)"
    elif command -v brew >/dev/null 2>&1; then
        PM="brew"
        OS_TYPE="macos"
        info "Detected brew (macOS $OS_ARCH)"
    else
        info "Could not detect package manager. Using tgz fallback."
    fi

    info "OS: $OS_TYPE ($OS_ARCH)"
}

install_dependencies() {
    banner "Installing dependencies"

    if [ -z "$PM" ]; then
        info "No package manager detected, skipping dependency install."
        return
    fi

    case "$PM" in
        pacman)
            sudo pacman -S --needed --noconfirm wget curl acl unzip tar base-devel git 2>/dev/null
            ;;
        apt-get)
            sudo apt-get install -y -qq wget curl acl unzip debsums 2>/dev/null
            ;;
        apk)
            sudo apk add --no-cache wget curl acl unzip tar 2>/dev/null
            ;;
        pkg)
            sudo pkg install -y wget curl unzip 2>/dev/null
            ;;
        brew)
            brew install wget curl unzip 2>/dev/null
            ;;
        *)
            sudo "$PM" install -y wget curl acl unzip 2>/dev/null
            ;;
    esac

    # Ensure rsyslog is available (Linux only)
    if [ "$OS_TYPE" = "linux" ]; then
        for f in /var/log/syslog /var/log/auth.log /var/log/secure; do
            if [ -e "$f" ]; then
                return
            fi
        done
        sudo "$PM" install -y rsyslog 2>/dev/null
    fi
}
########################################################

################ SPLUNK USER SETUP #####################
create_splunk_user() {
    banner "Creating splunk user"

    if id "splunk" >/dev/null 2>&1; then
        info "Splunk user already exists"
    else
        info "Creating splunk user"
        case "$OS_TYPE" in
            freebsd)
                sudo pw useradd splunk -d "$SPLUNK_HOME" -s /usr/sbin/nologin 2>/dev/null
                ;;
            macos)
                # macOS: create user via dscl
                sudo dscl . -create /Users/splunk 2>/dev/null
                sudo dscl . -create /Users/splunk UserShell /usr/bin/false 2>/dev/null
                sudo dscl . -create /Users/splunk NFSHomeDirectory "$SPLUNK_HOME" 2>/dev/null
                # Find a free UID above 500
                SPLUNK_UID=$(sudo dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
                SPLUNK_UID=$((SPLUNK_UID + 1))
                sudo dscl . -create /Users/splunk UniqueID "$SPLUNK_UID" 2>/dev/null
                sudo dscl . -create /Users/splunk PrimaryGroupID 20 2>/dev/null
                ;;
            *)
                sudo useradd splunk -d "$SPLUNK_HOME" 2>/dev/null
                ;;
        esac
    fi

    if [ "$OS_TYPE" != "macos" ]; then
        if ! getent group "splunk" >/dev/null 2>&1; then
            if [ "$OS_TYPE" = "freebsd" ]; then
                sudo pw groupadd splunk 2>/dev/null
                sudo pw usermod splunk -G splunk 2>/dev/null
            else
                sudo groupadd splunk 2>/dev/null
                sudo usermod -aG splunk splunk 2>/dev/null
            fi
        fi
    fi

    # Set splunk password non-interactively
    if [ "$OS_TYPE" = "freebsd" ]; then
        echo "$PASS" | sudo pw usermod splunk -h 0 2>/dev/null
    elif [ "$OS_TYPE" != "macos" ]; then
        echo "splunk:$PASS" | sudo chpasswd 2>/dev/null
    fi

    # Give splunk user ACL access to /var/log/
    if command -v setfacl >/dev/null 2>&1; then
        info "Setting ACL permissions on /var/log/"
        sudo setfacl -Rm g:splunk:rx /var/log/ 2>/dev/null
        sudo setfacl -Rdm g:splunk:rx /var/log/ 2>/dev/null
    fi

    # Allow package verification via sudo (Linux only)
    if [ "$OS_TYPE" = "linux" ] && [ -d /etc/sudoers.d ]; then
        if [ "$PM" = "apt-get" ] && command -v debsums >/dev/null 2>&1; then
            echo "splunk ALL=(ALL) NOPASSWD: $(which debsums) -as" | sudo tee /etc/sudoers.d/splunk >/dev/null
        elif command -v rpm >/dev/null 2>&1; then
            echo "splunk ALL=(ALL) NOPASSWD: $(which rpm) -Va" | sudo tee /etc/sudoers.d/splunk >/dev/null
        fi
        sudo chmod 440 /etc/sudoers.d/splunk 2>/dev/null
    fi

    sudo chown -R splunk:splunk "$SPLUNK_HOME" 2>/dev/null
}
########################################################

################ PACKAGE INSTALL #######################
download_and_install_package() {
    pkg_url="$1"

    if echo "$pkg_url" | grep -q '\.deb$'; then
        if ! download "$pkg_url" /tmp/splunk-pkg.deb; then
            error "Failed to download deb package"
            return 1
        fi
        sudo dpkg -i /tmp/splunk-pkg.deb
        rm -f /tmp/splunk-pkg.deb
    elif echo "$pkg_url" | grep -q '\.rpm$'; then
        if ! download "$pkg_url" /tmp/splunk-pkg.rpm; then
            error "Failed to download rpm package"
            return 1
        fi
        if command -v zypper >/dev/null 2>&1; then
            sudo zypper --no-gpg-checks install -y /tmp/splunk-pkg.rpm
        else
            sudo yum install --nogpgcheck /tmp/splunk-pkg.rpm -y 2>/dev/null || \
                sudo rpm -ivh /tmp/splunk-pkg.rpm 2>/dev/null
        fi
        rm -f /tmp/splunk-pkg.rpm
    elif echo "$pkg_url" | grep -q '\.tgz$'; then
        if ! download "$pkg_url" /tmp/splunk-pkg.tgz; then
            error "Failed to download tgz package"
            return 1
        fi
        info "Extracting to /opt/"
        sudo tar -xzf /tmp/splunk-pkg.tgz -C /opt/ 2>/dev/null
        rm -f /tmp/splunk-pkg.tgz
    else
        error "Unknown package type."
        return 1
    fi
}

install_splunk_package() {
    if [ "$MODE" = "indexer" ]; then
        banner "Installing Splunk Enterprise"
    else
        banner "Installing Splunk Universal Forwarder"
    fi

    if [ -x "$SPLUNK_HOME/bin/splunk" ]; then
        info "Splunk already installed at $SPLUNK_HOME. Proceeding to configure."
        return 0
    fi

    # Select URLs based on mode
    if [ "$MODE" = "indexer" ]; then
        pkg_deb="$idx_deb"; pkg_rpm="$idx_rpm"; pkg_tgz="$idx_tgz"
        old_pkg_deb="$old_idx_deb"; old_pkg_rpm="$old_idx_rpm"; old_pkg_tgz="$old_idx_tgz"
    else
        pkg_deb="$fwd_deb"; pkg_rpm="$fwd_rpm"; pkg_tgz="$fwd_tgz"
        old_pkg_deb="$old_fwd_deb"; old_pkg_rpm="$old_fwd_rpm"; old_pkg_tgz="$old_fwd_tgz"
    fi

    case "$PACKAGE" in
        auto)
            info "Auto-detecting best package format"

            # macOS — pick Intel vs Apple Silicon
            if [ "$OS_TYPE" = "macos" ]; then
                if [ "$OS_ARCH" = "arm64" ]; then
                    info "macOS Apple Silicon detected"
                    download_and_install_package "$m1_macos_tgz"
                else
                    info "macOS Intel detected"
                    download_and_install_package "$intel_macos_tgz"
                fi

            # FreeBSD — pick 13 vs 14 based on major version
            elif [ "$OS_TYPE" = "freebsd" ]; then
                if [ "${FREEBSD_MAJOR:-0}" -ge 14 ] 2>/dev/null; then
                    info "FreeBSD 14+ detected"
                    download_and_install_package "$free14_tgz"
                else
                    info "FreeBSD 13 (or older) detected"
                    download_and_install_package "$free13_tgz"
                fi

            # Linux — pick by package manager
            else
                case "$PM" in
                    apt-get)  download_and_install_package "$pkg_deb" ;;
                    dnf|yum)  download_and_install_package "$pkg_rpm" ;;
                    zypper)   download_and_install_package "$pkg_rpm" ;;
                    apk)      download_and_install_package "$pkg_tgz" ;;
                    pacman)   download_and_install_package "$pkg_tgz" ;;
                    *)        download_and_install_package "$pkg_tgz" ;;
                esac
            fi
            ;;
        deb)     download_and_install_package "$pkg_deb" ;;
        rpm)     download_and_install_package "$pkg_rpm" ;;
        tgz)     download_and_install_package "$pkg_tgz" ;;
        old_deb) download_and_install_package "$old_pkg_deb" ;;
        old_rpm) download_and_install_package "$old_pkg_rpm" ;;
        old_tgz) download_and_install_package "$old_pkg_tgz" ;;
        legacy_deb) download_and_install_package "$legacy_fwd_deb" ;;
        legacy_rpm) download_and_install_package "$legacy_fwd_rpm" ;;
        legacy_tgz) download_and_install_package "$legacy_fwd_tgz" ;;
        arm_deb) download_and_install_package "$arm_deb" ;;
        arm_rpm) download_and_install_package "$arm_rpm" ;;
        arm_tgz) download_and_install_package "$arm_tgz" ;;
        macos_intel) download_and_install_package "$intel_macos_tgz" ;;
        macos_m1)    download_and_install_package "$m1_macos_tgz" ;;
        free13)      download_and_install_package "$free13_tgz" ;;
        free14)      download_and_install_package "$free14_tgz" ;;
        *)
            error "Unknown package: $PACKAGE"
            exit 1
            ;;
    esac

    # Fallback chain if primary failed (Linux only)
    if [ ! -x "$SPLUNK_HOME/bin/splunk" ] && [ "$OS_TYPE" = "linux" ]; then
        error "Primary install failed. Trying fallback to 9.4.0..."
        case "$PM" in
            apt-get)       download_and_install_package "$old_pkg_deb" ;;
            dnf|yum|zypper) download_and_install_package "$old_pkg_rpm" ;;
            *)             download_and_install_package "$old_pkg_tgz" ;;
        esac
    fi

    # Ultimate fallback: try tgz (works on any distro, no package manager needed)
    if [ ! -x "$SPLUNK_HOME/bin/splunk" ] && [ "$OS_TYPE" = "linux" ]; then
        error "Package install failed. Trying tgz as last resort..."
        download_and_install_package "$pkg_tgz" || download_and_install_package "$old_pkg_tgz"
    fi

    if [ ! -x "$SPLUNK_HOME/bin/splunk" ]; then
        error "Splunk installation failed after fallback. Exiting."
        exit 1
    fi

    info "Splunk installed successfully."
}
########################################################

################ USER SEED #############################
# Write user-seed.conf BEFORE first start so Splunk 9.x+ boots with the
# correct admin password. Without this, Splunk 9.x has no default password
# and the old 'changeme' approach fails.
write_user_seed() {
    banner "Writing user-seed.conf"

    sudo mkdir -p "$SPLUNK_HOME/etc/system/local" 2>/dev/null

    if [ "$MODE" = "indexer" ]; then
        sudo sh -c "cat > $SPLUNK_HOME/etc/system/local/user-seed.conf << SEEDEOF
[user_info]
USERNAME = $SPLUNK_USERNAME
PASSWORD = $PASS
SEEDEOF"
        info "user-seed.conf written for $SPLUNK_USERNAME"
    else
        sudo sh -c "cat > $SPLUNK_HOME/etc/system/local/user-seed.conf << SEEDEOF
[user_info]
USERNAME = splunk
PASSWORD = $PASS
SEEDEOF"
        info "user-seed.conf written for splunk"
    fi
}
########################################################

################ START SPLUNK ##########################
ensure_splunk_running() {
    banner "Starting Splunk"

    if [ "$MODE" = "forwarder" ]; then
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" start --accept-license --no-prompt >/dev/null 2>&1
    else
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" start --accept-license --no-prompt >/dev/null 2>&1
    fi

    info "Waiting for Splunk to start..."
    local wait_count=0
    local max_wait=30
    while [ $wait_count -lt $max_wait ]; do
        if sudo -H -u splunk $SPLUNK_HOME/bin/splunk status &>/dev/null; then
            info "Splunk is running"
            break
        fi
        sleep 2
        wait_count=$((wait_count + 1))
        if [ $wait_count -eq $max_wait ]; then
            error "Splunk failed to start within expected time"
            error "Please check: sudo systemctl status SplunkForwarder"
            error "And check logs at: $SPLUNK_HOME/var/log/splunk/"
            exit 1
        fi
    done

    info "Splunk is running"
}
########################################################

############## INSTALL SPLUNK APP ######################
install_forwarder_app() {
    app_url="$1"
    download "$app_url" /tmp/app.spl
    if [ -f /tmp/app.spl ]; then
        sudo chown splunk:splunk /tmp/app.spl
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" install app /tmp/app.spl -update 1 -auth "splunk:$PASS" 2>/dev/null
        sudo rm -f /tmp/app.spl
    else
        error "Failed to download app from $app_url"
    fi
}

install_indexer_app() {
    app_url="$1"
    app_name="$2"
    info "Installing $app_name..."
    download "$app_url" /tmp/app.spl
    if [ -f /tmp/app.spl ]; then
        "$SPLUNK_HOME/bin/splunk" install app /tmp/app.spl -update 1 \
            -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
        rm -f /tmp/app.spl
        info "$app_name installed."
    else
        error "Failed to download $app_name"
    fi
}

install_ccdc_add_on() {
    banner "Installing CCDC Splunk add-on"
    install_forwarder_app "$GITHUB_URL/splunk-apps/ccdc-add-on.spl"
}

install_sysmon_add_on() {
    banner "Installing Sysmon for Linux Splunk add-on"
    install_forwarder_app "$GITHUB_URL/splunk-apps/splunk-add-on-for-sysmon-for-linux_100.tgz"

    # Configure sysmon inputs with correct index
    dir="$SPLUNK_HOME/etc/apps/Splunk_TA_sysmon-for-linux/local/"
    sudo mkdir -p "$dir"
    sudo chown -R splunk:splunk "$dir"
    # Pass 10 bytes min size for small config file
    download "$GITHUB_URL/splunk-configs/sysmon-inputs.conf" /tmp/sysmon-inputs.conf 10
    sudo chown splunk:splunk /tmp/sysmon-inputs.conf
    sudo mv /tmp/sysmon-inputs.conf "$dir/inputs.conf"
}

install_unix_linux_ta() {
    banner "Installing Splunk Add-on for Unix and Linux"
    install_forwarder_app "$GITHUB_URL/splunk-apps/splunk-add-on-for-unix-and-linux_920.tgz"
    info "Unix/Linux TA installed"
}

install_suricata() {
    banner "Installing Suricata (Rules & Config)"
    
    # 1. Install Suricata (Package)
    case "$PM" in
        apt-get)
            # Ubuntu/Debian - use PPA
            info "Adding Suricata PPA for Debian/Ubuntu..."
            sudo add-apt-repository -y ppa:oisf/suricata-stable 2>/dev/null
            sudo apt-get update -y 2>/dev/null
            sudo apt-get install -y suricata 2>/dev/null
            ;;
        yum)
            # RHEL/CentOS - use COPR
            info "Adding Suricata COPR repository for RHEL/CentOS..."
            sudo yum install epel-release yum-plugin-copr -y 2>/dev/null
            sudo yum copr enable @oisf/suricata-8.0 -y 2>/dev/null
            sudo yum update -y 2>/dev/null
            sudo yum install suricata -y 2>/dev/null
            ;;
        dnf)
            # Fedora - use COPR
            info "Adding Suricata COPR repository for Fedora..."
            sudo dnf install epel-release dnf-plugins-core -y 2>/dev/null
            sudo dnf copr enable @oisf/suricata-8.0 -y 2>/dev/null
            sudo dnf update -y 2>/dev/null
            sudo dnf install suricata -y 2>/dev/null
            ;;
        zypper)
            # OpenSUSE
            info "Installing Suricata on OpenSUSE..."
            sudo zypper install -y suricata 2>/dev/null
            ;;
        pacman)
            # Arch Linux
            info "Installing Suricata on Arch Linux..."
            sudo pacman -S --needed --noconfirm suricata 2>/dev/null
            ;;
        *)
            warn "Suricata install not supported for $PM"
            return 1
            ;;
    esac

    # 2. Download and extract rules (ET Open)
    info "Downloading Emerging Threats Open rules..."
    cd /tmp/
    if curl -LO https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || \
       wget https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || \
       fetch https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null; then
       
       tar -xvzf emerging.rules.tar.gz 2>/dev/null
       sudo mkdir -p /etc/suricata/rules 2>/dev/null
       sudo mv rules/*.rules /etc/suricata/rules/ 2>/dev/null
       sudo chmod 644 /etc/suricata/rules/*.rules 2>/dev/null
       rm -rf emerging.rules.tar.gz rules/
    else
       warn "Failed to download ET rules."
    fi

    # 3. Download working suricata.yaml config
    CONF="/etc/suricata/suricata.yaml"
    info "Downloading working suricata.yaml config..."
    if download "$GITHUB_URL/splunk-configs/suricata.yaml" /tmp/suricata.yaml; then
        sudo cp /tmp/suricata.yaml "$CONF"
        rm -f /tmp/suricata.yaml
        info "Installed working suricata.yaml"
    else
        warn "Failed to download suricata.yaml, using existing config"
    fi

    # 4. Configure HOME_NET and af-packet interface
    if [ -f "$CONF" ]; then
        # Detect Interface/IP
        IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
        [ -z "$IFACE" ] && IFACE="eth0"
        IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2; exit}')
        HOST_IP=${IP%%/*}
        
        info "Detected interface: $IFACE with IP: $HOST_IP"

        # Update HOME_NET
        sudo sed -i -e "s|HOME_NET:.*|HOME_NET: \"${HOST_IP}\"|" "$CONF"

        # Update ALL eth0 references to actual interface (af-packet, pcap, etc.)
        sudo sed -i -e "s|eth0|${IFACE}|g" "$CONF"

        info "Updated HOME_NET and all interface references to $IFACE"
    else
        warn "suricata.yaml not found at $CONF"
    fi

    # 5. Update sysconfig/default file (RPM/Debian distros set interface here)
    if [ -f /etc/sysconfig/suricata ]; then
        info "Updating /etc/sysconfig/suricata with interface $IFACE"
        sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" /etc/sysconfig/suricata
        sudo sed -i -e "s|-i ens[0-9]*|-i ${IFACE}|g" /etc/sysconfig/suricata
        sudo sed -i -e "s|-i enp[0-9a-z]*|-i ${IFACE}|g" /etc/sysconfig/suricata
    elif [ -f /etc/default/suricata ]; then
        info "Updating /etc/default/suricata with interface $IFACE"
        sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" /etc/default/suricata
        sudo sed -i -e "s|-i ens[0-9]*|-i ${IFACE}|g" /etc/default/suricata
        sudo sed -i -e "s|-i enp[0-9a-z]*|-i ${IFACE}|g" /etc/default/suricata
    fi

    # 6. Update systemd service file (fallback if not using sysconfig)
    for SVCFILE in /usr/lib/systemd/system/suricata.service /etc/systemd/system/suricata.service /lib/systemd/system/suricata.service; do
        if [ -f "$SVCFILE" ]; then
            info "Updating systemd service file: $SVCFILE"
            sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" "$SVCFILE"
            break
        fi
    done

    # 7. Restart Suricata
    # Reload systemd daemon (required after fresh install)
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl enable suricata 2>/dev/null
        info "Restarting Suricata via systemctl..."
        sudo systemctl restart suricata
        sleep 3
        if sudo systemctl is-active --quiet suricata; then
            info "Suricata is running"
            SURICATA_SUCCESSFUL=true
        else
            warn "Suricata failed to start. Check 'systemctl status suricata'"
        fi
    elif command -v service >/dev/null 2>&1; then
        info "Restarting Suricata via service..."
        sudo service suricata restart
        sleep 3
        if sudo service suricata status >/dev/null 2>&1; then
            info "Suricata is running"
            SURICATA_SUCCESSFUL=true
        else
            warn "Suricata failed to start. Check 'service suricata status'"
        fi
    else
        warn "No init system found (systemctl/service). Please restart Suricata manually."
    fi

    # 5. Add Splunk Monitor configuration for Stamus Networks App
    LOG_DIR="/var/log/suricata"
    LOG_FILE="$LOG_DIR/eve.json"
    
    # Ensure splunk user can read suricata logs
    sudo chmod 755 "$LOG_DIR" 2>/dev/null
    sudo setfacl -R -m u:splunk:rx "$LOG_DIR" 2>/dev/null || sudo chmod -R o+rx "$LOG_DIR" 2>/dev/null
    
    # Wait for eve.json to be created
    sleep 5
    
    if [ -f "$LOG_FILE" ]; then
        # Monitor specific file with correct sourcetype for Stamus app
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$LOG_FILE" -index "suricata" -sourcetype "suricata" -auth "splunk:$PASS" 2>/dev/null
        info "Monitored $LOG_FILE -> index=suricata, sourcetype=suricata"
    elif [ -d "$LOG_DIR" ]; then
        # Fallback: Monitor directory (catches eve.json when created)
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$LOG_DIR" -index "suricata" -sourcetype "suricata" -auth "splunk:$PASS" 2>/dev/null
        info "Monitored $LOG_DIR -> index=suricata, sourcetype=suricata"
        warn "eve.json not found yet - Suricata may still be initializing"
    else
        warn "Suricata log directory not found at $LOG_DIR. Check service status."
    fi
}

install_nginx_ta() {
    banner "Installing NGINX TA"

    # Only install if NGINX is present
    if ! command -v nginx >/dev/null 2>&1 && [ ! -d /etc/nginx ]; then
        info "NGINX not detected, skipping NGINX TA"
        return
    fi

    install_forwarder_app "$GITHUB_URL/splunk-apps/splunk-add-on-for-nginx_330.tgz"

    # Configure NGINX log monitoring with proper sourcetype
    dir="$SPLUNK_HOME/etc/apps/Splunk_TA_nginx/local/"
    sudo mkdir -p "$dir"
    sudo chown -R splunk:splunk "$dir"
    cat > /tmp/nginx-inputs.conf << 'NGINXEOF'
[monitor:///var/log/nginx/access.log]
disabled = 0
sourcetype = nginx:plus:access
index = web

[monitor:///var/log/nginx/error.log]
disabled = 0
sourcetype = nginx:plus:error
index = web
NGINXEOF
    sudo chown splunk:splunk /tmp/nginx-inputs.conf
    sudo mv /tmp/nginx-inputs.conf "$dir/inputs.conf"
    info "NGINX TA installed with log monitoring"
}

install_apache_ta() {
    banner "Installing Apache TA"

    # Only install if Apache/httpd is present
    if ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1 && \
       [ ! -d /etc/apache2 ] && [ ! -d /etc/httpd ]; then
        info "Apache not detected, skipping Apache TA"
        return
    fi

    install_forwarder_app "$GITHUB_URL/splunk-apps/splunk-add-on-for-apache-web-server_221.tgz"

    # Configure Apache log monitoring with proper sourcetype
    dir="$SPLUNK_HOME/etc/apps/Splunk_TA_apache/local/"
    sudo mkdir -p "$dir"
    sudo chown -R splunk:splunk "$dir"
    cat > /tmp/apache-inputs.conf << 'APACHEEOF'
[monitor:///var/log/apache2/access.log]
disabled = 0
sourcetype = apache:access
index = web

[monitor:///var/log/apache2/error.log]
disabled = 0
sourcetype = apache:error
index = web

[monitor:///var/log/httpd/access_log]
disabled = 0
sourcetype = apache:access
index = web

[monitor:///var/log/httpd/error_log]
disabled = 0
sourcetype = apache:error
index = web
APACHEEOF
    sudo chown splunk:splunk /tmp/apache-inputs.conf
    sudo mv /tmp/apache-inputs.conf "$dir/inputs.conf"
    info "Apache TA installed with log monitoring"
}
########################################################

################ MONITOR SETUP #########################
add_monitor() {
    source_path="$1"
    index="$2"
    sourcetype="$3"

    if [ -e "$source_path" ] || [ -d "$source_path" ]; then
        if [ -n "$sourcetype" ]; then
            sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$source_path" -index "$index" -sourcetype "$sourcetype" -auth "splunk:$PASS" 2>/dev/null
        else
            sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$source_path" -index "$index" -auth "splunk:$PASS" 2>/dev/null
        fi
        info "Added monitor: $source_path -> $index"
    fi
}

add_scripted_input() {
    script_cmd="$1"
    index="$2"
    interval="$3"
    sourcetype="$4"

    sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add exec "$script_cmd" \
        -index "$index" -interval "$interval" -sourcetype "$sourcetype" \
        -auth "splunk:$PASS" 2>/dev/null
    info "Added scripted input: $sourcetype (every ${interval}s)"
}

add_system_logs() {
    banner "Adding system log monitors"
    info "Some will fail due to distribution differences -- this is normal."

    INDEX="system"
    add_monitor "/var/log/syslog" "$INDEX"
    add_monitor "/var/log/messages" "$INDEX"
    add_monitor "/var/log/auth.log" "$INDEX"
    add_monitor "/var/log/secure" "$INDEX"
    add_monitor "/var/log/audit/audit.log" "$INDEX"
    add_monitor "/var/log/daemon.log" "$INDEX"
    add_monitor "/var/log/kern.log" "$INDEX"

    # Arch-specific: systemd journal
    if [ "$PM" = "pacman" ] && [ -d /var/log/journal ]; then
        add_monitor "/var/log/journal" "$INDEX" "systemd:journal"
        sudo usermod -aG systemd-journal splunk 2>/dev/null
    fi
}

add_web_logs() {
    banner "Adding web server log monitors"
    INDEX="web"
    add_monitor "/var/log/apache2/" "$INDEX"
    add_monitor "/var/log/httpd/" "$INDEX"
    add_monitor "/var/log/nginx/" "$INDEX"
}

add_firewall_logs() {
    banner "Adding firewall log monitors"
    INDEX="network"

    if command -v firewall-cmd >/dev/null 2>&1; then
        info "Enabling firewalld logging"
        sudo firewall-cmd --set-log-denied=all 2>/dev/null
        add_monitor "/var/log/firewalld" "$INDEX"
    fi

    add_monitor "/var/log/kern.log" "$INDEX"
    add_monitor "/var/log/pflog" "$INDEX"
}

add_package_manager_logs() {
    banner "Adding package manager log monitors"
    INDEX="system"
    add_monitor "/var/log/apt/" "$INDEX"
    add_monitor "/var/log/dpkg.log" "$INDEX"
    add_monitor "/var/log/dnf.log" "$INDEX"
    add_monitor "/var/log/dnf.rpm.log" "$INDEX"
    add_monitor "/var/log/yum.log" "$INDEX"
    add_monitor "/var/log/zypp/" "$INDEX"

    if [ "$PM" = "pacman" ]; then
        add_monitor "/var/log/pacman.log" "$INDEX"
        sudo setfacl -m g:splunk:r /var/log/pacman.log 2>/dev/null
    fi
}

add_cron_logs() {
    banner "Adding cron log monitors"
    INDEX="system"
    add_monitor "/var/log/cron" "$INDEX"
    add_monitor "/var/log/cron.log" "$INDEX"
}

add_mail_logs() {
    banner "Adding mail log monitors"
    INDEX="system"
    add_monitor "/var/log/mail.log" "$INDEX"
    add_monitor "/var/log/mail.err" "$INDEX"
    add_monitor "/var/log/maillog" "$INDEX"
}

add_dns_logs() {
    banner "Adding DNS log monitors"
    INDEX="dns"
    add_monitor "/var/log/named/" "$INDEX"
    add_monitor "/var/log/dnsmasq.log" "$INDEX"
}

add_scripted_inputs() {
    banner "Adding scripted inputs for service/network visibility"

    # Service inventory - every 5 minutes
    add_scripted_input "/bin/sh -c 'systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null || service --status-all 2>/dev/null'" \
        "system" "300" "service_inventory"

    # Active network connections - every 60 seconds
    add_scripted_input "/bin/sh -c 'ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null'" \
        "network" "60" "netstat"

    # Listening ports - every 5 minutes
    add_scripted_input "/bin/sh -c 'ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null'" \
        "network" "300" "listening_ports"

    # DNS resolver check - every hour (detect resolver hijack)
    add_scripted_input "/bin/sh -c 'cat /etc/resolv.conf 2>/dev/null'" \
        "dns" "3600" "resolv_conf"

    # Package Inventory (rpm/dpkg) - every hour
    if [ "$PM" = "apt-get" ]; then
         add_scripted_input "/bin/sh -c 'dpkg-query -W -f=\"\${Package}|\${Version}|\${Architecture}|\${Status}\n\"'" \
            "system" "3600" "package_inventory"
    else
         add_scripted_input "/bin/sh -c 'rpm -qa --qf \"%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}|%{INSTALLTIME}\n\"'" \
            "system" "3600" "package_inventory"
    fi
}

install_suricata() {
    banner "Installing and Configuring Suricata"

    # Install package if missing
    if ! command -v suricata >/dev/null 2>&1; then
        info "Installing Suricata package..."
        case "$PM" in
            apt-get)
                # Ubuntu/Debian - use PPA
                info "Adding Suricata PPA for Debian/Ubuntu..."
                sudo add-apt-repository ppa:oisf/suricata-stable -y 2>/dev/null
                sudo apt-get update -y 2>/dev/null
                sudo apt-get install -y suricata 2>/dev/null
                ;;
            yum)
                # RHEL/CentOS - use COPR
                info "Adding Suricata COPR repository for RHEL/CentOS..."
                sudo yum install epel-release yum-plugin-copr -y 2>/dev/null
                sudo yum copr enable @oisf/suricata-8.0 -y 2>/dev/null
                sudo yum update -y 2>/dev/null
                sudo yum install suricata -y 2>/dev/null
                ;;
            dnf)
                # Fedora - use COPR
                info "Adding Suricata COPR repository for Fedora..."
                sudo dnf install epel-release dnf-plugins-core -y 2>/dev/null
                sudo dnf copr enable @oisf/suricata-8.0 -y 2>/dev/null
                sudo dnf update -y 2>/dev/null
                sudo dnf install suricata -y 2>/dev/null
                ;;
            zypper)
                # OpenSUSE
                info "Installing Suricata on OpenSUSE..."
                sudo zypper install -y suricata 2>/dev/null
                ;;
            pacman)
                # Arch Linux
                info "Installing Suricata on Arch Linux..."
                sudo pacman -S --needed --noconfirm suricata 2>/dev/null
                ;;
            *)
                warn "Package manager $PM not supported for Suricata auto-install. Assuming installed."
                ;;
        esac
    fi

    # Download and extract rules (ET Open)
    info "Downloading Emerging Threats Open rules..."
    cd /tmp/ && { curl -LO https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || wget https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || fetch https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null; }
    tar -xvzf emerging.rules.tar.gz 2>/dev/null && sudo mkdir -p /etc/suricata/rules 2>/dev/null && sudo mv rules/*.rules /etc/suricata/rules/ 2>/dev/null 
    sudo chmod 644 /etc/suricata/rules/*.rules 2>/dev/null
    rm -rf emerging.rules.tar.gz rules/

    # Download working suricata.yaml config
    CONF="/etc/suricata/suricata.yaml"
    info "Downloading working suricata.yaml config..."
    if download "$GITHUB_URL/splunk-configs/suricata.yaml" /tmp/suricata.yaml; then
        sudo cp /tmp/suricata.yaml "$CONF"
        rm -f /tmp/suricata.yaml
        info "Installed working suricata.yaml"
    else
        warn "Failed to download suricata.yaml, using existing config"
    fi

    # Configure HOME_NET and af-packet interface
    if [ -f "$CONF" ]; then
        IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
        [ -z "$IFACE" ] && IFACE="eth0"
        IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2; exit}')
        HOST_IP=${IP%%/*}
        [ -z "$HOST_IP" ] && HOST_IP="127.0.0.1"

        info "Detected interface: $IFACE with IP: $HOST_IP"

        # Update HOME_NET
        sudo sed -i -e "s|HOME_NET:.*|HOME_NET: \"${HOST_IP}\"|" "$CONF"

        # Update ALL eth0 references to actual interface (af-packet, pcap, etc.)
        sudo sed -i -e "s|eth0|${IFACE}|g" "$CONF"

        info "Updated HOME_NET and all interface references to $IFACE"
    fi

    # Update sysconfig/default file (RPM/Debian distros set interface here)
    if [ -f /etc/sysconfig/suricata ]; then
        info "Updating /etc/sysconfig/suricata with interface $IFACE"
        sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" /etc/sysconfig/suricata
        sudo sed -i -e "s|-i ens[0-9]*|-i ${IFACE}|g" /etc/sysconfig/suricata
        sudo sed -i -e "s|-i enp[0-9a-z]*|-i ${IFACE}|g" /etc/sysconfig/suricata
    elif [ -f /etc/default/suricata ]; then
        info "Updating /etc/default/suricata with interface $IFACE"
        sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" /etc/default/suricata
        sudo sed -i -e "s|-i ens[0-9]*|-i ${IFACE}|g" /etc/default/suricata
        sudo sed -i -e "s|-i enp[0-9a-z]*|-i ${IFACE}|g" /etc/default/suricata
    fi

    # Update systemd service file (fallback if not using sysconfig)
    for SVCFILE in /usr/lib/systemd/system/suricata.service /etc/systemd/system/suricata.service /lib/systemd/system/suricata.service; do
        if [ -f "$SVCFILE" ]; then
            info "Updating systemd service file: $SVCFILE"
            sudo sed -i -e "s|-i eth0|-i ${IFACE}|g" "$SVCFILE"
            break
        fi
    done

    # Reload systemd daemon (required after fresh install)
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl enable suricata 2>/dev/null
        info "Restarting Suricata via systemctl..."
        sudo systemctl restart suricata
        sleep 3
        if sudo systemctl is-active --quiet suricata; then
            info "Suricata is running"
            SURICATA_SUCCESSFUL=true
        else
            warn "Suricata failed to start. Check 'systemctl status suricata'"
        fi
    elif command -v service >/dev/null 2>&1; then
        info "Restarting Suricata via service..."
        sudo service suricata restart
        sleep 3
        if sudo service suricata status >/dev/null 2>&1; then
            info "Suricata is running"
            SURICATA_SUCCESSFUL=true
        else
            warn "Suricata failed to start. Check 'service suricata status'"
        fi
    else
        warn "No init system found (systemctl/service). Please restart Suricata manually."
    fi
    
    # Add Splunk Monitor configuration for Stamus Networks App
    LOG_DIR="/var/log/suricata"
    LOG_FILE="$LOG_DIR/eve.json"
    
    # Ensure splunk user can read suricata logs
    sudo chmod 755 "$LOG_DIR" 2>/dev/null
    sudo setfacl -R -m u:splunk:rx "$LOG_DIR" 2>/dev/null || sudo chmod -R o+rx "$LOG_DIR" 2>/dev/null
    
    # Wait for eve.json to be created
    sleep 3
    
    if [ -f "$LOG_FILE" ]; then
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$LOG_FILE" -index "suricata" -sourcetype "suricata" -auth "splunk:$PASS" 2>/dev/null
        info "Monitored $LOG_FILE -> index=suricata, sourcetype=suricata"
    elif [ -d "$LOG_DIR" ]; then
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$LOG_DIR" -index "suricata" -sourcetype "suricata" -auth "splunk:$PASS" 2>/dev/null
        info "Monitored $LOG_DIR -> index=suricata, sourcetype=suricata"
        warn "eve.json not found yet - Suricata may still be initializing"
    else
        warn "Suricata log directory not found at $LOG_DIR"
    fi
}

add_redbaron_logs() {
    banner "Adding RedBaron2 log monitors"
    
    # RedBaron2 (Linux) logs to /var/log/rb2/ by default
    # Logs: yara, firewall, process, scan
    RB2_LOG_DIR="/var/log/rb2"
    INDEX="edr"

    if [ -d "$RB2_LOG_DIR" ]; then
        info "RedBaron2 log directory found at $RB2_LOG_DIR"
        
        # Ensure splunk user can read the logs
        sudo setfacl -R -m u:splunk:r "$RB2_LOG_DIR" 2>/dev/null || \
            sudo chmod -R o+r "$RB2_LOG_DIR" 2>/dev/null
        
        # Add monitors for each log type
        add_monitor "$RB2_LOG_DIR/yara" "$INDEX" "redbaron:yara"
        add_monitor "$RB2_LOG_DIR/firewall" "$INDEX" "redbaron:firewall"
        add_monitor "$RB2_LOG_DIR/process" "$INDEX" "redbaron:process"
        add_monitor "$RB2_LOG_DIR/scan" "$INDEX" "redbaron:scan"
        
        info "RedBaron2 monitors added for yara, firewall, process, scan"
    else
        # Create directory for when RedBaron2 is deployed
        info "RedBaron2 log directory not found. Creating $RB2_LOG_DIR for future use..."
        sudo mkdir -p "$RB2_LOG_DIR"
        sudo chmod 755 "$RB2_LOG_DIR"
        
        # Pre-configure monitors anyway (they'll activate when logs appear)
        add_monitor "$RB2_LOG_DIR/yara" "$INDEX" "redbaron:yara"
        add_monitor "$RB2_LOG_DIR/firewall" "$INDEX" "redbaron:firewall"
        add_monitor "$RB2_LOG_DIR/process" "$INDEX" "redbaron:process"
        add_monitor "$RB2_LOG_DIR/scan" "$INDEX" "redbaron:scan"
        
        info "RedBaron2 monitors pre-configured (logs will appear when rb2 is deployed)"
    fi
}

setup_all_monitors() {
    install_ccdc_add_on
    install_unix_linux_ta
    install_suricata

    add_system_logs
    add_web_logs
    install_nginx_ta
    install_apache_ta
    add_firewall_logs
    add_package_manager_logs
    add_cron_logs
    add_mail_logs
    add_dns_logs
    add_scripted_inputs
    add_redbaron_logs
}
########################################################

################ AUDITD ################################
install_auditd() {
    banner "Installing auditd"

    if [ -z "$PM" ]; then
        info "No package manager. Skipping auditd."
        return 1
    fi

    case "$PM" in
        pacman)
            sudo pacman -S --needed --noconfirm audit 2>/dev/null
            ;;
        apt-get)
            sudo apt-get install -y -qq auditd 2>/dev/null
            ;;
        *)
            sudo "$PM" install -y auditd 2>/dev/null || sudo "$PM" install -y audit 2>/dev/null
            ;;
    esac

    # Enable and start
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable auditd 2>/dev/null
        sudo systemctl start auditd 2>/dev/null
    else
        sudo service auditd start 2>/dev/null
    fi

    # Download and apply CCDC audit rules
    if [ -e /var/log/audit/audit.log ]; then
        info "auditd running. Downloading CCDC audit rules..."
        download "$GITHUB_URL/auditd/ccdc.rules" /tmp/auditd.rules
        if [ -f /tmp/auditd.rules ]; then
            if [ -f /etc/audit/rules.d/audit.rules ]; then
                sudo mv /tmp/auditd.rules /etc/audit/rules.d/audit.rules
            elif [ -f /etc/audit/audit.rules ]; then
                sudo mv /tmp/auditd.rules /etc/audit/audit.rules
            fi
            sudo systemctl restart auditd 2>/dev/null || sudo service auditd restart 2>/dev/null
        fi

        # Set ACL for splunk to read audit logs
        sudo setfacl -m g:splunk:r /var/log/audit/audit.log 2>/dev/null
        sudo setfacl -dm g:splunk:r /var/log/audit/ 2>/dev/null

        AUDITD_SUCCESSFUL=true
        info "auditd installed and configured."
    else
        error "auditd installation failed."
        return 1
    fi
}
########################################################

################ SNOOPY ################################
install_snoopy() {
    banner "Installing Snoopy (official installer)"

    SNOOPY_LOG="/var/log/snoopy.log"

    # Use the official install-snoopy.sh one-liner (thanks ippsec)
    download "https://github.com/a2o/snoopy/raw/install/install/install-snoopy.sh" /tmp/install-snoopy.sh 100
    if [ ! -f /tmp/install-snoopy.sh ]; then
        error "Failed to download snoopy installer"
        return 1
    fi

    chmod 755 /tmp/install-snoopy.sh
    if sudo /tmp/install-snoopy.sh stable; then
        # Configure snoopy to log to our file
        SNOOPY_CONFIG="/etc/snoopy.ini"
        sudo mkdir -p "$(dirname "$SNOOPY_CONFIG")"
        echo "[snoopy]" > /etc/snoopy.ini
        echo "output = file:$SNOOPY_LOG" >> /etc/snoopy.ini

        sudo touch "$SNOOPY_LOG"
        sudo chmod 644 "$SNOOPY_LOG"
        # Ensure splunk can read it via ACL
        sudo setfacl -m g:splunk:r "$SNOOPY_LOG" 2>/dev/null

        # Add snoopy log monitor to Splunk
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add monitor "$SNOOPY_LOG" -index "snoopy" -sourcetype "snoopy" -auth "splunk:$PASS" 2>/dev/null

        SNOOPY_SUCCESSFUL=true
        
        # Verify preload
        if ! grep -q "snoopy" /etc/ld.so.preload 2>/dev/null; then
            warn "Snoopy NOT found in /etc/ld.so.preload. Logging may not work until you fix this."
        else
            info "Snoopy configured in /etc/ld.so.preload."
        fi

        info "Snoopy installed. Note: restart server for full coverage."
    else
        error "Snoopy installation failed"
        rm -f /tmp/install-snoopy.sh
        return 1
    fi

    rm -f /tmp/install-snoopy.sh
    return 0
}
########################################################

################ SYSMON ################################
install_sysmon() {
    banner "Installing Sysmon for Linux"

    # Check if already installed
    if command -v sysmon >/dev/null 2>&1; then
        info "Sysmon already installed"
        install_sysmon_add_on
        SYSMON_SUCCESSFUL=true
        return 0
    fi

    # Install from Microsoft's package repository based on distro
    # Also install kernel headers for eBPF/CO-RE support (fixes status=12)
    KERNEL_VER=$(uname -r)
    case "$PM" in
        apt-get)
            # Ubuntu/Debian official logic
            info "Registering Microsoft key and feed (DEB)..."
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                # Detect Ubuntu vs Debian
                if [ "$ID" = "ubuntu" ]; then
                     wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
                elif [ "$ID" = "debian" ] || [ "$ID_LIKE" = "debian" ]; then
                     # Debian uses specific version IDs (e.g. 11, 12)
                     DEB_VER="${VERSION_ID%%.*}"
                     [ -z "$DEB_VER" ] && DEB_VER="12" # Fallback
                     wget -q "https://packages.microsoft.com/config/debian/$DEB_VER/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
                fi
                sudo dpkg -i /tmp/packages-microsoft-prod.deb 2>/dev/null
                rm -f /tmp/packages-microsoft-prod.deb
            fi
            
            sudo apt-get update -qq
            
            # Kernel headers
            info "Installing kernel headers for eBPF support..."
            sudo apt-get install -y "linux-headers-$KERNEL_VER" 2>/dev/null
            
            sudo apt-get install -y sysmonforlinux
            ;;
            
        dnf|yum)
            # Fedora/RHEL/CentOS official logic
            info "Registering Microsoft key and feed (RPM)..."
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" = "fedora" ]; then
                    sudo rpm -Uvh "https://packages.microsoft.com/config/fedora/$(rpm -E %fedora)/packages-microsoft-prod.rpm" 2>/dev/null
                elif [ "$ID" = "rhel" ] || [ "$ID" = "centos" ] || [ "$ID_LIKE" = "rhel" ]; then
                    # RHEL uses VERSION_ID (e.g. 8.x -> 8)
                    RHEL_VER="${VERSION_ID%%.*}"
                    [ -z "$RHEL_VER" ] && RHEL_VER="8" # Fallback
                    sudo rpm -Uvh "https://packages.microsoft.com/config/rhel/$RHEL_VER/packages-microsoft-prod.rpm" 2>/dev/null
                else
                    # Fallback to RHEL 8 if unknown
                    sudo rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm 2>/dev/null
                fi
            fi
            
            # Kernel headers
            info "Installing kernel headers for eBPF support..."
            sudo "$PM" install -y "kernel-devel-$KERNEL_VER" "kernel-headers-$KERNEL_VER" 2>/dev/null

            sudo "$PM" install -y sysmonforlinux
            ;;
            
        zypper)
            # OpenSUSE/SLES official logic
            # Simplistic handling for SLES 15/12
            sudo rpm -Uvh https://packages.microsoft.com/config/sles/15/packages-microsoft-prod.rpm 2>/dev/null
            sudo zypper install -y sysmonforlinux
            ;;
            
        *)
            warn "Sysmon install not supported for $PM"
            return 1
            ;;
    esac

    if ! command -v sysmon >/dev/null 2>&1; then
        error "Sysmon installation failed — binary not found after install"
        return 1
    fi

    # Write sysmon config XML
    info "Writing sysmon config..."
    cat > /tmp/sysmon-config.xml << 'SYSMONEOF'
<Sysmon schemaversion="4.81">
  <EventFiltering>
    <!-- Log all process creation -->
    <RuleGroup name="" groupRelation="or">
      <ProcessCreate onmatch="exclude">
        <Image condition="is">/opt/splunkforwarder/bin/splunkd</Image>
        <Image condition="end with">sysmon</Image>
      </ProcessCreate>
    </RuleGroup>
    <!-- Log file creation in sensitive dirs -->
    <RuleGroup name="" groupRelation="or">
      <FileCreate onmatch="include">
        <TargetFilename condition="begin with">/etc/</TargetFilename>
        <TargetFilename condition="begin with">/root/</TargetFilename>
        <TargetFilename condition="begin with">/tmp/</TargetFilename>
        <TargetFilename condition="begin with">/var/spool/cron</TargetFilename>
      </FileCreate>
    </RuleGroup>
    <!-- Log network connections (exclude Splunk) -->
    <RuleGroup name="" groupRelation="or">
      <NetworkConnect onmatch="exclude">
        <Image condition="is">/opt/splunkforwarder/bin/splunkd</Image>
      </NetworkConnect>
    </RuleGroup>
  </EventFiltering>
</Sysmon>
SYSMONEOF

    sudo sysmon -accepteula -i /tmp/sysmon-config.xml 2>/dev/null
    rm -f /tmp/sysmon-config.xml

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable sysmon 2>/dev/null
        sudo systemctl start sysmon 2>/dev/null
    fi

    info "Sysmon installed and running"
    install_sysmon_add_on
    SYSMON_SUCCESSFUL=true
    return 0
}
########################################################

################ IPTABLES LOGGING ######################
setup_iptables_logging() {
    banner "Setting up iptables network logging"

    # Install iptables if needed
    if ! command -v iptables >/dev/null 2>&1; then
        info "Installing iptables..."
        if command -v yum >/dev/null 2>&1; then
            sudo yum install -y iptables iptables-services 2>/dev/null
        elif command -v apt-get >/dev/null 2>&1; then
            echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
            echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables iptables-persistent 2>/dev/null
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm iptables 2>/dev/null
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y iptables iptables-services 2>/dev/null
        fi
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        error "iptables not available. Skipping."
        return 1
    fi

    # Outbound connection logging
    if ! sudo iptables -L OUTPUT -n 2>/dev/null | grep -q "LOG.*NETOUT:"; then
        sudo iptables -I OUTPUT 1 -m state --state NEW -j LOG --log-prefix "NETOUT: " --log-level 4
        info "Added outbound connection logging (NETOUT:)"
    else
        info "Outbound logging rule already exists"
    fi

    # Inbound connection logging
    if ! sudo iptables -L INPUT -n 2>/dev/null | grep -q "LOG.*NETIN:"; then
        sudo iptables -I INPUT 1 -m state --state NEW -j LOG --log-prefix "NETIN: " --log-level 4
        info "Added inbound connection logging (NETIN:)"
    else
        info "Inbound logging rule already exists"
    fi

    # Persist rules
    info "Making iptables rules persistent..."
    if [ -f /etc/debian_version ]; then
        sudo mkdir -p /etc/iptables
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
        if command -v netfilter-persistent >/dev/null 2>&1; then
            sudo netfilter-persistent save 2>/dev/null
            sudo systemctl enable netfilter-persistent 2>/dev/null
        fi
    elif [ -f /etc/redhat-release ]; then
        sudo mkdir -p /etc/sysconfig
        sudo iptables-save | sudo tee /etc/sysconfig/iptables >/dev/null
        if sudo systemctl list-unit-files 2>/dev/null | grep -q iptables.service; then
            sudo systemctl enable iptables.service 2>/dev/null
        fi
    elif [ -f /etc/arch-release ]; then
        sudo mkdir -p /etc/iptables
        sudo iptables-save | sudo tee /etc/iptables/iptables.rules >/dev/null
        sudo systemctl enable iptables.service 2>/dev/null
    else
        sudo mkdir -p /etc/iptables
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
    fi

    IPTABLES_LOGGING_SUCCESSFUL=true
    info "iptables logging configured (NETIN:/NETOUT: prefixes)"
}

########################################################

########### INDEXER-SPECIFIC FUNCTIONS #################
backup_original() {
    banner "Backing up original Splunk configurations"
    mkdir -p "$BACKUP_DIR/splunkORIGINAL"
    cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunkORIGINAL" 2>/dev/null
    info "Original backup saved to $BACKUP_DIR/splunkORIGINAL"
}

set_banner() {
    banner "Setting global banner"
    cat > "$SPLUNK_HOME/etc/system/local/global-banner.conf" << 'BANNEREOF'
[BANNER_MESSAGE_SINGLETON]
global_banner.visible = true
global_banner.message = WARNING: NO UNAUTHORIZED ACCESS. This is property of Wild West Parks Inc. Unauthorized users will be prosecuted and tried to the furthest extent of the law!
global_banner.background_color = red
BANNEREOF
    info "Global banner configured."
}

secure_permissions() {
    banner "Setting secure file permissions"
    # Restrict access but keep splunk user ownership so Splunk can still write its configs
    chmod -R 700 "$SPLUNK_HOME/etc/system/local" 2>/dev/null
    chmod -R 700 "$SPLUNK_HOME/etc/system/default" 2>/dev/null
    chown -R splunk:splunk "$SPLUNK_HOME" 2>/dev/null
    info "Permissions secured."
}

change_admin_password() {
    banner "Changing admin password"

    info "Attempting to set password for user: $SPLUNK_USERNAME"

    # If user-seed.conf was used on first boot, password is already set to PASS.
    # Verify we can authenticate with it.
    if "$SPLUNK_HOME/bin/splunk" login -auth "$SPLUNK_USERNAME:$PASS" 2>/dev/null; then
        info "Password is already set correctly (from user-seed.conf)."
        return 0
    fi

    # Try changing from the old default password (pre-9.x or pre-existing install)
    if "$SPLUNK_HOME/bin/splunk" edit user "$SPLUNK_USERNAME" \
        -password "$PASS" \
        -auth "$SPLUNK_USERNAME:$OG_SPLUNK_PASSWORD" 2>/dev/null; then
        info "Admin password changed from old default."
        return 0
    fi

    # Last resort: try common defaults
    for old_pass in "changeme" "admin" "password"; do
        if "$SPLUNK_HOME/bin/splunk" edit user "$SPLUNK_USERNAME" \
            -password "$PASS" \
            -auth "$SPLUNK_USERNAME:$old_pass" 2>/dev/null; then
            info "Admin password changed (was: $old_pass)."
            return 0
        fi
    done

    error "Failed to change admin password. You may need to reset it manually."
    error "Try: $SPLUNK_HOME/bin/splunk edit user $SPLUNK_USERNAME -password <new> -auth $SPLUNK_USERNAME:<current>"
}

remove_unauthorized_users() {
    banner "Removing unauthorized users"
    USERS=$("$SPLUNK_HOME/bin/splunk" list user \
        -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null | \
        grep -v "$SPLUNK_USERNAME" | awk '{print $2}')

    for u in $USERS; do
        if [ -n "$u" ] && [ "$u" != "splunk-system-user" ]; then
            "$SPLUNK_HOME/bin/splunk" remove user "$u" \
                -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
            info "Removed user: $u"
        fi
    done
}

create_indexes() {
    banner "Creating Splunk indexes"
    for idx in $INDEXES; do
        "$SPLUNK_HOME/bin/splunk" add index "$idx" \
            -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
        info "Created index: $idx"
    done
}

enable_listener() {
    banner "Enabling receiving on port $Receiver_Port"
    "$SPLUNK_HOME/bin/splunk" enable listen "$Receiver_Port" \
        -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
    info "Listening on port $Receiver_Port"
}

set_admin_roles() {
    banner "Setting admin roles"
    "$SPLUNK_HOME/bin/splunk" edit user "$SPLUNK_USERNAME" \
        -role admin -role can_delete \
        -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
    info "Admin user has admin + can_delete roles."
}

install_indexer_apps() {
    banner "Installing indexer apps"

    install_indexer_app "$GITHUB_URL/splunk-apps/ccdc-app.spl" "CCDC Splunk App"
    install_indexer_app "$GITHUB_URL/splunk-apps/ccdc-add-on.spl" "CCDC Add-on"

    if [ -n "$GITHUB_URL" ]; then
        install_indexer_app "$GITHUB_URL/splunk-apps/windows-security-operations-center_20.tgz" "Windows SOC App"
        install_indexer_app "$GITHUB_URL/splunk-apps/sysmon-security-monitoring-app-for-splunk_4013.tgz" "Sysmon Security Monitoring"
        install_indexer_app "$GITHUB_URL/splunk-apps/linux-audit-log-hex-value-decoder_100.tgz" "Audit Hex Decoder"
        install_indexer_app "$GITHUB_URL/splunk-apps/cyberchef-for-splunk_114.tgz" "CyberChef for Splunk"
    fi

    # Stamus Networks App (User provided .tgz)
    info "Installing Stamus Networks App..."
    STAMUS_TGZ_LOCAL="$(dirname "$0")/splunk-apps/stamus-networks-app-for-splunk_104.tgz"
    
    # Also check LOCAL_FOLDER
    if [ -n "$LOCAL_FOLDER" ] && [ -f "$LOCAL_FOLDER/splunk-apps/stamus-networks-app-for-splunk_104.tgz" ]; then
        STAMUS_TGZ_LOCAL="$LOCAL_FOLDER/splunk-apps/stamus-networks-app-for-splunk_104.tgz"
    fi
    
    if [ -f "$STAMUS_TGZ_LOCAL" ]; then
        info "Installing local Stamus App ($STAMUS_TGZ_LOCAL)..."
        # Remove any existing stamus apps to avoid conflict
        for d in "$SPLUNK_HOME/etc/apps/stamus"* "$SPLUNK_HOME/etc/apps/Stamus"* ; do
            [ -d "$d" ] && sudo rm -rf "$d"
        done
        
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" install app "$STAMUS_TGZ_LOCAL" -update 1 -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
        
        # The app extracts as 'stamus_for_splunk'
        STAMUS_INSTALLED_DIR="$SPLUNK_HOME/etc/apps/stamus_for_splunk"
        
        # Fallback: detect app directory name if different
        if [ ! -d "$STAMUS_INSTALLED_DIR" ]; then
            STAMUS_INSTALLED_DIR=$(find "$SPLUNK_HOME/etc/apps" -maxdepth 1 -type d -iname "*stamus*" | head -n 1)
        fi
        
        if [ -n "$STAMUS_INSTALLED_DIR" ] && [ -d "$STAMUS_INSTALLED_DIR" ]; then
            info "Stamus App installed to $STAMUS_INSTALLED_DIR"
            
            # Configure macro to use our suricata index
            MACRO_CONF="$STAMUS_INSTALLED_DIR/local/macros.conf"
            sudo mkdir -p "$(dirname "$MACRO_CONF")"
            cat <<'STAMUSEOF' | sudo tee "$MACRO_CONF" >/dev/null
[stamus_index]
definition = index=suricata
iseval = 0
STAMUSEOF
            
            sudo chown -R splunk:splunk "$STAMUS_INSTALLED_DIR"
            info "Configured Stamus macro: index=suricata"
        else
            warn "Stamus App installed via CLI but directory check failed."
        fi
    else
        warn "Local Stamus App package not found at $STAMUS_TGZ_LOCAL"
        warn "Skipping Stamus installation."
    fi

    # Palo Alto apps
    info "Installing Palo Alto apps..."
    download "https://github.com/PaloAltoNetworks/Splunk-Apps/archive/refs/tags/v8.1.3.zip" /tmp/palo.zip 1000
    if [ -f /tmp/palo.zip ]; then
        unzip -o /tmp/palo.zip -d /tmp/palo-apps/ 2>/dev/null
        
        # Dynamic discovery of apps to avoid hardcoded version paths
        TA_DIR=$(find /tmp/palo-apps -maxdepth 2 -type d -name "Splunk_TA_paloalto" | head -n 1)
        APP_DIR=$(find /tmp/palo-apps -maxdepth 2 -type d -name "SplunkforPaloAltoNetworks" | head -n 1)

        if [ -n "$TA_DIR" ] && [ -d "$TA_DIR" ] && [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ]; then
            sudo mv "$TA_DIR" "$SPLUNK_HOME/etc/apps/" 2>/dev/null
            sudo mv "$APP_DIR" "$SPLUNK_HOME/etc/apps/" 2>/dev/null
            
            # Ensure permissions
            sudo chown -R splunk:splunk "$SPLUNK_HOME/etc/apps/Splunk_TA_paloalto"
            sudo chown -R splunk:splunk "$SPLUNK_HOME/etc/apps/SplunkforPaloAltoNetworks"
            
            info "Palo Alto apps installed."
        else
            error "Failed to locate Palo Alto apps in extracted zip."
            warn "Listing extracted files for debug:"
            ls -R /tmp/palo-apps/ | head -n 20
        fi
        rm -rf /tmp/palo.zip /tmp/palo-apps/
    fi

    # Enable and make visible all installed apps
    banner "Enabling all installed apps"
    for app_dir in "$SPLUNK_HOME"/etc/apps/*/; do
        app_name=$(basename "$app_dir")
        # Skip Splunk internal/framework apps
        case "$app_name" in
            splunk_*|learned|legacy|launcher|sample_app|introspection_*|SplunkForwarder|SplunkLightForwarder|SplunkDeploymentServerConfig|journald_input|log_event_alert_action|webhook_alert_action|alert_logevent|alert_webhook|appsbrowser|search) continue ;;
        esac
        # Ensure app.conf exists with enabled + visible
        mkdir -p "$app_dir/local" 2>/dev/null
        app_conf="$app_dir/local/app.conf"
        if [ ! -f "$app_conf" ]; then
            cat > "$app_conf" << APPEOF
[install]
state = enabled

[ui]
is_visible = true
APPEOF
            info "Enabled app: $app_name"
        else
            # If app.conf exists but app is disabled, enable it
            if grep -q "state = disabled" "$app_conf" 2>/dev/null; then
                sed -i 's/state = disabled/state = enabled/g' "$app_conf"
                info "Re-enabled app: $app_name"
            fi
            # Ensure visibility
            if ! grep -q "is_visible" "$app_conf" 2>/dev/null; then
                if grep -q "\[ui\]" "$app_conf" 2>/dev/null; then
                    sed -i '/\[ui\]/a is_visible = true' "$app_conf"
                else
                    printf "\n[ui]\nis_visible = true\n" >> "$app_conf"
                fi
                info "Made visible: $app_name"
            fi
        fi
    done
    chown -R splunk:splunk "$SPLUNK_HOME/etc/apps" 2>/dev/null
    info "All apps enabled and visible."
}

configure_indexer_firewall() {
    banner "Configuring indexer firewall rules"

    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -I INPUT 1 -p tcp -m multiport --dport 8000,9443 -j ACCEPT 2>/dev/null
        sudo iptables -I INPUT 1 -p tcp --dport "$Receiver_Port" -j ACCEPT 2>/dev/null
        sudo iptables -I INPUT 1 -p tcp --dport 8089 -j ACCEPT 2>/dev/null
        info "iptables rules added for ports 8000, 8089, 9443, $Receiver_Port"
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --add-port=8000/tcp 2>/dev/null
        sudo firewall-cmd --permanent --add-port=9443/tcp 2>/dev/null
        sudo firewall-cmd --permanent --add-port="$Receiver_Port/tcp" 2>/dev/null
        sudo firewall-cmd --permanent --add-port=8089/tcp 2>/dev/null
        sudo firewall-cmd --reload 2>/dev/null
        info "firewalld rules added."
    fi
}

backup_final() {
    banner "Backing up final Splunk configurations"
    mkdir -p "$BACKUP_DIR/splunk"
    cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunk" 2>/dev/null
    info "Final backup saved to $BACKUP_DIR/splunk"
}
########################################################

################ C2 DETECTION ##########################
setup_c2_detection() {
    banner "Deploying C2 Detection saved searches"

    # Create dns index if it doesn't exist
    "$SPLUNK_HOME/bin/splunk" add index dns -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null

    # Deploy into the existing ccdc-app (installed from SPL)
    CCDC_APP="$SPLUNK_HOME/etc/apps/ccdc-app"
    mkdir -p "$CCDC_APP/local"

    # Deploy saved searches for behavioral C2 detection
    if [ -f "$SCRIPT_DIR/splunk-configs/savedsearches.conf" ]; then
        cp "$SCRIPT_DIR/splunk-configs/savedsearches.conf" "$CCDC_APP/local/savedsearches.conf"
        info "Deployed savedsearches.conf from local configs"
    else
        download "$GITHUB_URL/splunk-configs/savedsearches.conf" /tmp/savedsearches.conf
        if [ -f /tmp/savedsearches.conf ]; then
            mv /tmp/savedsearches.conf "$CCDC_APP/local/savedsearches.conf"
            info "Downloaded and deployed savedsearches.conf"
        else
            error "Failed to deploy saved searches"
            return 1
        fi
    fi

    chown -R splunk:splunk "$CCDC_APP" 2>/dev/null

    C2_DETECTION_SUCCESSFUL=true
    info "C2 Detection deployed to $CCDC_APP"
    info "Saved searches will auto-detect:"
    info "  - Beaconing (periodic low-jitter connections)"
    info "  - DNS anomalies (DGA / tunneling / exfiltration)"
    info "  - Non-standard port connections"
    info "  - Unusual process network activity"
    info "  - New outbound connections"
}
########################################################

################ FIREWALL SYSLOG #######################
setup_firewall_syslog() {
    banner "Configuring rsyslog for firewall syslog reception"

    info "Firewall IP: $FIREWALL_IP"

    # Install rsyslog if needed
    if ! command -v rsyslogd >/dev/null 2>&1; then
        info "Installing rsyslog..."
        if [ -n "$PM" ]; then
            sudo "$PM" install -y rsyslog 2>/dev/null
        fi
    fi

    # Add rsyslog config for firewall log reception
    cat <<RSYSLOGEOF | sudo tee -a /etc/rsyslog.conf >/dev/null

# Firewall syslog reception - added by CraniacCombo splunk.sh
module(load="imudp")
input(type="imudp" port="514")
if \$fromhost-ip == '$FIREWALL_IP' and \$msg contains 'AccessControlRuleAction' then /var/log/fw_network.log
& stop
if \$fromhost-ip == '$FIREWALL_IP' then /var/log/fw_system.log
RSYSLOGEOF

    # Restart rsyslog
    sudo systemctl restart rsyslog 2>/dev/null || sudo service rsyslog restart 2>/dev/null

    # Add Splunk monitors for firewall logs
    "$SPLUNK_HOME/bin/splunk" add monitor /var/log/fw_network.log -index network -sourcetype "firewall:network" \
        -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null
    "$SPLUNK_HOME/bin/splunk" add monitor /var/log/fw_system.log -index system -sourcetype "firewall:system" \
        -auth "${SPLUNK_USERNAME}:${PASS}" 2>/dev/null

    FIREWALL_SYSLOG_SUCCESSFUL=true
    info "Firewall syslog configured:"
    info "  Network logs: /var/log/fw_network.log -> index=network"
    info "  System logs:  /var/log/fw_system.log -> index=system"
}
########################################################

################ FORWARDER MAIN ########################
run_forwarder() {
    info "Splunk Forwarder deployment starting"
    info "Indexer: $INDEXER | Port: $Receiver_Port | Time: $(date '+%Y-%m-%d %H:%M:%S')"

    autodetect_os
    install_dependencies
    install_splunk_package
    create_splunk_user
    write_user_seed
    ensure_splunk_running

    # Login
    sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" login -auth "splunk:$PASS" 2>/dev/null

    # Configure forward server
    banner "Configuring forward server"
    info "Setting forward server to $INDEXER:$Receiver_Port"
    sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" add forward-server "$INDEXER:$Receiver_Port" -auth "splunk:$PASS" 2>/dev/null
    sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" set deploy-poll "$INDEXER:8089" -auth "splunk:$PASS" 2>/dev/null

    # Setup all monitors
    setup_all_monitors

    # Enable boot-start
    banner "Enabling boot-start"
    sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" stop 2>/dev/null
    if command -v systemctl >/dev/null 2>&1; then
        info "Enabling systemd service"
        sudo "$SPLUNK_HOME/bin/splunk" enable boot-start -systemd-managed 1 -user splunk 2>/dev/null
        sudo systemctl enable SplunkForwarder 2>/dev/null
        sudo systemctl start SplunkForwarder 2>/dev/null
    elif [ "$OS_TYPE" = "freebsd" ]; then
        info "Enabling FreeBSD rc.d service"
        sudo "$SPLUNK_HOME/bin/splunk" enable boot-start -user splunk 2>/dev/null
        sudo sysrc splunk_enable=YES 2>/dev/null
        sudo service splunk start 2>/dev/null
    elif [ "$OS_TYPE" = "macos" ]; then
        info "Enabling macOS launchd service"
        sudo "$SPLUNK_HOME/bin/splunk" enable boot-start -user splunk 2>/dev/null
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" start 2>/dev/null
    else
        info "Using splunk start (no systemd)"
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" start 2>/dev/null
    fi

    sudo chown -R splunk:splunk "$SPLUNK_HOME"

    # Install additional logging sources (Linux only — auditd/snoopy/sysmon are Linux-specific)
    if [ "$SPLUNK_ONLY" = "false" ] && [ "$OS_TYPE" = "linux" ]; then
        banner "Installing additional logging sources"

        if [ "$INSTALL_AUDITD" = "true" ]; then
            install_auditd
        fi

        if [ "$INSTALL_SNOOPY" = "true" ]; then
            install_snoopy || error "Snoopy installation failed"
        fi

        if [ "$INSTALL_SYSMON" = "true" ]; then
            install_sysmon
        fi

        if [ "$INSTALL_SURICATA" = "true" ]; then
            install_suricata
        fi
    elif [ "$OS_TYPE" != "linux" ]; then
        info "Non-Linux OS ($OS_TYPE) — skipping auditd/snoopy/sysmon (Linux-only tools)"
    else
        info "SPLUNK_ONLY=true, skipping additional logging sources."
    fi

    # iptables logging (Linux only)
    if [ "$INSTALL_IPTABLES_LOGGING" = "true" ] && [ "$SPLUNK_ONLY" = "false" ] && [ "$OS_TYPE" = "linux" ]; then
        setup_iptables_logging
    fi

    # Final restart
    banner "Final restart"
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl restart SplunkForwarder 2>/dev/null
    else
        sudo -H -u splunk "$SPLUNK_HOME/bin/splunk" restart 2>/dev/null
    fi

    # Summary
    banner "Forwarder Deployment Complete"
    echo "  OS:         $OS_TYPE ($OS_KERNEL $OS_ARCH)"
    echo "  Indexer:    $INDEXER:$Receiver_Port"
    echo "  Home:       $SPLUNK_HOME"
    if [ "$OS_TYPE" = "linux" ]; then
        echo "  Auditd:     $AUDITD_SUCCESSFUL"
        echo "  Snoopy:     $SNOOPY_SUCCESSFUL"
        echo "  Sysmon:     $SYSMON_SUCCESSFUL"
        echo "  Suricata:   $SURICATA_SUCCESSFUL"
        echo "  iptables:   $IPTABLES_LOGGING_SUCCESSFUL"
    fi
    echo ""
}
########################################################

################ INDEXER MAIN ##########################
run_indexer() {
    info "Splunk Indexer setup starting"
    info "Port: $Receiver_Port | Time: $(date '+%Y-%m-%d %H:%M:%S')"
    INDEXES="sysmon suricata snoopy dns web system network"

    autodetect_os
    install_dependencies
    install_splunk_package
    write_user_seed
    ensure_splunk_running

    backup_original
    set_banner
    secure_permissions
    change_admin_password
    remove_unauthorized_users
    create_indexes
    enable_listener
    set_admin_roles
    install_indexer_apps
    configure_indexer_firewall

    # C2 detection
    if [ "$INSTALL_C2_DETECTION" = "true" ]; then
        setup_c2_detection
    fi

    # Firewall syslog reception
    if [ -n "$FIREWALL_IP" ]; then
        setup_firewall_syslog
    fi

    # iptables logging
    if [ "$INSTALL_IPTABLES_LOGGING" = "true" ] && [ "$SPLUNK_ONLY" = "false" ]; then
        setup_iptables_logging
    fi

    # Restart to apply all changes
    banner "Restarting Splunk"
    chown -R splunk:splunk "$SPLUNK_HOME" 2>/dev/null
    "$SPLUNK_HOME/bin/splunk" restart 2>/dev/null

    backup_final

    # Summary
    banner "Indexer Setup Complete"
    echo "  Web UI:       https://<this_host>:8000"
    echo "  Receiving:    port $Receiver_Port"
    echo "  Indexes:      $INDEXES"
    echo "  User:         $SPLUNK_USERNAME"
    echo "  C2 Detection: $C2_DETECTION_SUCCESSFUL"
    echo "  FW Syslog:    $FIREWALL_SYSLOG_SUCCESSFUL"
    echo "  iptables:     $IPTABLES_LOGGING_SUCCESSFUL"
    echo ""
}
########################################################

######################## MAIN ##########################
if [ "$MODE" = "indexer" ]; then
    run_indexer
else
    run_forwarder
fi

echo "${GREEN}######### DONE! #########${NC}"
