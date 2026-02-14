#!/bin/bash

#############################################
# SUID Removal Script
# Removes SUID bit from specified binaries
# Must be run with root privileges
#############################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Starting SUID removal process..."
echo ""

# Array of binaries to remove SUID from
BINARIES=("find" "vim" "python3")

# Function to remove SUID bit from a binary
remove_suid() {
    local binary_name="$1"
    local binary_path
    
    # Find the binary path
    binary_path=$(which "$binary_name" 2>/dev/null)
    
    if [ -z "$binary_path" ]; then
        echo -e "${YELLOW}[WARN]${NC} Binary '$binary_name' not found in PATH"
        return 1
    fi
    
    # Check if SUID bit is set
    if [ -u "$binary_path" ]; then
        echo -e "${YELLOW}[ACTION]${NC} Removing SUID bit from: $binary_path"
        chmod u-s "$binary_path"
        
        # Verify removal
        if [ ! -u "$binary_path" ]; then
            echo -e "${GREEN}[SUCCESS]${NC} SUID bit removed from $binary_path"
        else
            echo -e "${RED}[ERROR]${NC} Failed to remove SUID bit from $binary_path"
            return 1
        fi
    else
        echo -e "${GREEN}[INFO]${NC} SUID bit not set on $binary_path (no action needed)"
    fi
    
    return 0
}

# Process each binary
for binary in "${BINARIES[@]}"; do
    remove_suid "$binary"
    echo ""
done

echo -e "${GREEN}[COMPLETE]${NC} SUID removal process finished"
