#!/bin/sh

# LD_PRELOAD Rootkit Detection Script
# Enhanced to detect the "Father" rootkit and other LD_PRELOAD-based threats

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================
# Requirements Check
# ========================================

printf "${BLUE}========================================${NC}\n"
printf "${BLUE}LD_PRELOAD Rootkit Detection - Pre-flight Check${NC}\n"
printf "${BLUE}========================================${NC}\n\n"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    printf "${RED}[FATAL]${NC} This script must be run as root for full system scanning.\n"
    printf "${YELLOW}[INFO]${NC} Some checks require root privileges to access /proc and system files.\n"
    printf "${YELLOW}[INFO]${NC} Please run with: sudo $0\n\n"
    exit 1
fi
printf "${GREEN}[OK]${NC} Running as root (UID: $(id -u))\n"

# Required tools
REQUIRED_TOOLS="strings grep cat ps find wc sort comm head"
MISSING_TOOLS=""

for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool >/dev/null 2>&1; then
        if [ -z "$MISSING_TOOLS" ]; then
            printf "\n${BLUE}Checking for required tools...${NC}\n"
        fi
        printf "${RED}[MISSING]${NC} $tool not found\n"
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

# Check for optional but recommended tools (removed netstat/ss since we don't use them)
OPTIONAL_TOOLS="lsof"
MISSING_OPTIONAL=""

for tool in $OPTIONAL_TOOLS; do
    if ! command -v $tool >/dev/null 2>&1; then
        if [ -z "$MISSING_OPTIONAL" ]; then
            printf "\n${BLUE}Checking for optional tools...${NC}\n"
        fi
        printf "${YELLOW}[WARN]${NC} $tool not found (optional, but recommended)\n"
        MISSING_OPTIONAL="$MISSING_OPTIONAL $tool"
    fi
done

# Exit if critical tools are missing
if [ -n "$MISSING_TOOLS" ]; then
    printf "\n${RED}[FATAL]${NC} Missing required tools:$MISSING_TOOLS\n"
    printf "${YELLOW}[INFO]${NC} Please install the missing tools before running this script.\n"
    printf "${YELLOW}[INFO]${NC} On Debian/Ubuntu: apt-get install coreutils procps findutils grep\n"
    printf "${YELLOW}[INFO]${NC} On RHEL/CentOS: yum install coreutils procps-ng findutils grep\n"
    printf "${YELLOW}[INFO]${NC} On Alpine: apk add coreutils procps findutils grep\n\n"
    exit 1
fi

printf "\n${GREEN}[OK]${NC} All required tools are available.\n"

# Check /proc filesystem
if [ ! -d /proc ]; then
    printf "${RED}[FATAL]${NC} /proc filesystem not found. This script requires /proc to scan processes.\n\n"
    exit 1
fi
printf "${GREEN}[OK]${NC} /proc filesystem is accessible.\n\n"

# Default to normal commands
CMD_ECHO="echo"
CMD_LS="ls"
CMD_CAT="cat"
CMD_PS="ps"
CMD_NETSTAT="netstat"
CMD_FIND="find"

# Check for busybox and override if available (static binaries bypass LD_PRELOAD hooks)
if command -v busybox >/dev/null 2>&1; then
    printf "${GREEN}[INFO]${NC} BusyBox found, using it for commands (bypasses LD_PRELOAD hooks).\n"
    CMD_ECHO="busybox echo"
    CMD_LS="busybox ls"
    CMD_CAT="busybox cat"
    CMD_PS="busybox ps"
    CMD_FIND="busybox find"
    BUSYBOX_AVAILABLE=1
else
    printf "${YELLOW}[WARN]${NC} BusyBox not found, falling back to standard commands (may be hooked).\n"
    BUSYBOX_AVAILABLE=0
fi

printf "\n${BLUE}========================================${NC}\n"
printf "${BLUE}LD_PRELOAD Rootkit Detection - Father Rootkit Scanner${NC}\n"
printf "${BLUE}========================================${NC}\n\n"

# 1. Check current LD_PRELOAD environment variable
printf "${BLUE}[1] Checking LD_PRELOAD environment variable...${NC}\n"
if [ -n "$LD_PRELOAD" ]; then
    printf "${RED}[ALERT]${NC} LD_PRELOAD is set: ${RED}$LD_PRELOAD${NC}\n"
else
    printf "${GREEN}[OK]${NC} LD_PRELOAD environment variable is not set.\n"
fi

# 2. Check /etc/ld.so.preload file
printf "\n${BLUE}[2] Checking /etc/ld.so.preload file...${NC}\n"
if [ -f /etc/ld.so.preload ]; then
    printf "${RED}[ALERT]${NC} /etc/ld.so.preload exists:\n"
    $CMD_LS -al /etc/ld.so.preload
    
    # Get file size
    FILESIZE=$(stat -c%s /etc/ld.so.preload 2>/dev/null || wc -c < /etc/ld.so.preload)
    
    if [ "$FILESIZE" -gt 0 ]; then
        printf "${RED}[ALERT]${NC} File size: ${RED}${FILESIZE} bytes${NC} - File is NOT empty!\n"
        
        # Try multiple methods to read the file (rootkit may hook some)
        printf "${YELLOW}[INFO]${NC} Attempting to read file contents:\n"
        
        # Method 1: BusyBox cat
        printf "\n${YELLOW}Method 1 (BusyBox cat):${NC}\n"
        PRELOAD_BB=$($CMD_CAT /etc/ld.so.preload 2>/dev/null)
        if [ -n "$PRELOAD_BB" ]; then
            printf "${RED}$PRELOAD_BB${NC}\n"
        else
            printf "${YELLOW}[WARN]${NC} BusyBox cat returned empty (possible hook)\n"
        fi
        
        # Method 2: Direct shell read
        printf "\n${YELLOW}Method 2 (Shell read):${NC}\n"
        if [ -r /etc/ld.so.preload ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                printf "${RED}%s${NC}\n" "$line"
            done < /etc/ld.so.preload
        fi
        
        # Method 3: Hex dump to see raw content
        printf "\n${YELLOW}Method 3 (Hex dump):${NC}\n"
        if command -v xxd >/dev/null 2>&1; then
            xxd /etc/ld.so.preload | head -5
        elif command -v hexdump >/dev/null 2>&1; then
            hexdump -C /etc/ld.so.preload | head -5
        elif command -v od >/dev/null 2>&1; then
            od -A x -t x1z -v /etc/ld.so.preload | head -5
        else
            printf "${YELLOW}[WARN]${NC} No hex dump tool available\n"
        fi
        
    else
        printf "${YELLOW}[WARN]${NC} /etc/ld.so.preload exists but is empty (0 bytes).\n"
    fi
else
    printf "${GREEN}[OK]${NC} /etc/ld.so.preload does not exist.\n"
fi

# 3. Scan all running processes for LD_PRELOAD in their environment
printf "\n${BLUE}[3] Scanning running processes for LD_PRELOAD usage...${NC}\n"
FOUND_PRELOAD=0
for pid in /proc/[0-9]*; do
    if [ -f "$pid/environ" ]; then
        PROC_PRELOAD=$(strings "$pid/environ" 2>/dev/null | grep "^LD_PRELOAD=" | cut -d= -f2-)
        if [ -n "$PROC_PRELOAD" ]; then
            PROC_NAME=$(cat "$pid/comm" 2>/dev/null || echo "unknown")
            printf "${RED}[ALERT]${NC} Process ${YELLOW}$(basename $pid)${NC} (${PROC_NAME}) has LD_PRELOAD: ${RED}$PROC_PRELOAD${NC}\n"
            FOUND_PRELOAD=1
        fi
    fi
done
if [ $FOUND_PRELOAD -eq 0 ]; then
    printf "${GREEN}[OK]${NC} No processes found with LD_PRELOAD set.\n"
fi

# 4. Check process memory maps for suspicious libraries
printf "\n${BLUE}[4] Checking process memory maps for suspicious preloaded libraries...${NC}\n"
SUSPICIOUS_LIBS=0
for pid in /proc/[0-9]*; do
    if [ -f "$pid/maps" ]; then
        # Look for .so files in unusual locations (not in /lib, /usr/lib, etc.)
        SUSPICIOUS=$(grep '\.so' "$pid/maps" 2>/dev/null | grep -v '/lib/' | grep -v '/usr/lib/' | grep -v '/lib64/' | grep -v '/usr/lib64/' | grep -v '\[' | awk '{print $6}' | sort -u)
        if [ -n "$SUSPICIOUS" ]; then
            PROC_NAME=$(cat "$pid/comm" 2>/dev/null || echo "unknown")
            printf "${YELLOW}[WARN]${NC} Process ${YELLOW}$(basename $pid)${NC} (${PROC_NAME}) has suspicious libraries:\n"
            echo "$SUSPICIOUS" | while read lib; do
                if [ -n "$lib" ]; then
                    printf "  ${RED}$lib${NC}\n"
                    SUSPICIOUS_LIBS=1
                fi
            done
        fi
    fi
done
if [ $SUSPICIOUS_LIBS -eq 0 ]; then
    printf "${GREEN}[OK]${NC} No suspicious libraries found in process memory maps.\n"
fi

# 5. Father rootkit specific: Check for hidden processes via GID discrepancies
printf "\n${BLUE}[5] Checking for hidden processes (Father rootkit GID hiding)...${NC}\n"
if [ $BUSYBOX_AVAILABLE -eq 1 ]; then
    # Compare output of busybox ps vs regular ps
    BUSYBOX_PS_COUNT=$(busybox ps | wc -l)
    REGULAR_PS_COUNT=$(ps aux 2>/dev/null | wc -l || ps -ef | wc -l)
    
    if [ $BUSYBOX_PS_COUNT -ne $REGULAR_PS_COUNT ]; then
        DIFF=$((BUSYBOX_PS_COUNT - REGULAR_PS_COUNT))
        printf "${RED}[ALERT]${NC} Process count mismatch detected! BusyBox: $BUSYBOX_PS_COUNT, Regular: $REGULAR_PS_COUNT (Diff: $DIFF)\n"
        printf "${YELLOW}[INFO]${NC} This may indicate hidden processes. Father rootkit hides processes by GID.\n"
    else
        printf "${GREEN}[OK]${NC} Process counts match between BusyBox and regular ps.\n"
    fi
else
    printf "${YELLOW}[SKIP]${NC} BusyBox not available, cannot compare process listings.\n"
fi


# 6. Check for file hiding (Father rootkit hides files with specific prefix)
printf "\n${BLUE}[6] Checking for file hiding discrepancies...${NC}\n"
if [ $BUSYBOX_AVAILABLE -eq 1 ]; then
    # Compare ls output in common directories
    for dir in /tmp /var/tmp /dev/shm /root; do
        if [ -d "$dir" ]; then
            BUSYBOX_COUNT=$(busybox ls -A "$dir" 2>/dev/null | wc -l)
            REGULAR_COUNT=$(ls -A "$dir" 2>/dev/null | wc -l)
            
            if [ $BUSYBOX_COUNT -ne $REGULAR_COUNT ]; then
                printf "${RED}[ALERT]${NC} File count mismatch in $dir! BusyBox: $BUSYBOX_COUNT, Regular: $REGULAR_COUNT\n"
                printf "${YELLOW}[INFO]${NC} Hidden files may be present. Comparing outputs...\n"
                
                # Show files only visible to busybox
                BUSYBOX_FILES=$(busybox ls -A "$dir" 2>/dev/null | sort)
                REGULAR_FILES=$(ls -A "$dir" 2>/dev/null | sort)
                
                printf "${YELLOW}Files only visible to BusyBox:${NC}\n"
                TMPFILE_BB=$(mktemp)
                TMPFILE_REG=$(mktemp)
                echo "$BUSYBOX_FILES" > "$TMPFILE_BB"
                echo "$REGULAR_FILES" > "$TMPFILE_REG"
                comm -23 "$TMPFILE_BB" "$TMPFILE_REG" | while read file; do
                    printf "  ${RED}$dir/$file${NC}\n"
                done
                rm -f "$TMPFILE_BB" "$TMPFILE_REG"
            fi
        fi
    done
    printf "${GREEN}[OK]${NC} File listing comparison complete.\n"
else
    printf "${YELLOW}[SKIP]${NC} BusyBox not available, cannot compare file listings.\n"
fi

# 7. Check for common Father rootkit library names
printf "\n${BLUE}[7] Searching for common rootkit library files...${NC}\n"
ROOTKIT_PATTERNS="father libfather libprocesshider lib_preload libhide"
FOUND_ROOTKIT_FILES=0

for pattern in $ROOTKIT_PATTERNS; do
    if command -v find >/dev/null 2>&1; then
        FOUND_FILES=$($CMD_FIND / -name "*$pattern*.so" 2>/dev/null)
        if [ -n "$FOUND_FILES" ]; then
            printf "${RED}[ALERT]${NC} Found potential rootkit files matching '$pattern':\n"
            echo "$FOUND_FILES" | while read file; do
                printf "  ${RED}$file${NC}\n"
                $CMD_LS -al "$file" 2>/dev/null
            done
            FOUND_ROOTKIT_FILES=1
        fi
    fi
done

if [ $FOUND_ROOTKIT_FILES -eq 0 ]; then
    printf "${GREEN}[OK]${NC} No obvious rootkit library files found.\n"
fi

# 8. Check for suspicious kernel modules (LKM rootkits)
printf "\n${BLUE}[8] Checking for suspicious kernel modules...${NC}\n"
if command -v lsmod >/dev/null 2>&1; then
    # Common rootkit module names
    ROOTKIT_MODULES="diamorphine reptile suterusu"
    FOUND_SUSPICIOUS=0
    
    for mod in $ROOTKIT_MODULES; do
        if lsmod | grep -q "^$mod"; then
            printf "${RED}[ALERT]${NC} Suspicious kernel module detected: ${RED}$mod${NC}\n"
            FOUND_SUSPICIOUS=1
        fi
    done
    
    # Check for hidden modules (modules in /sys/module but not in lsmod)
    if [ -d /sys/module ]; then
        for moddir in /sys/module/*; do
            modname=$(basename "$moddir")
            if ! lsmod | grep -q "^$modname"; then
                # Skip built-in modules and common false positives
                if [ -f "$moddir/refcnt" ] && [ ! -f "$moddir/initstate" ]; then
                    printf "${YELLOW}[WARN]${NC} Module in /sys/module but not in lsmod: ${YELLOW}$modname${NC}\n"
                    FOUND_SUSPICIOUS=1
                fi
            fi
        done
    fi
    
    if [ $FOUND_SUSPICIOUS -eq 0 ]; then
        printf "${GREEN}[OK]${NC} No suspicious kernel modules detected.\n"
    fi
else
    printf "${YELLOW}[SKIP]${NC} lsmod not available, cannot check kernel modules.\n"
fi

# 9. Check for LD_PRELOAD in /proc/*/maps (loaded libraries)
printf "\n${BLUE}[9] Checking for actively loaded suspicious libraries...${NC}\n"
FOUND_LOADED=0
for pid in /proc/[0-9]*; do
    if [ -f "$pid/maps" ]; then
        # Look for libraries with suspicious names or in unusual locations
        SUSPICIOUS=$(grep '\.so' "$pid/maps" 2>/dev/null | grep -E '(father|hide|preload|rootkit|backdoor)' | awk '{print $6}' | sort -u)
        if [ -n "$SUSPICIOUS" ]; then
            PROC_NAME=$(cat "$pid/comm" 2>/dev/null || echo "unknown")
            printf "${RED}[ALERT]${NC} Process ${YELLOW}$(basename $pid)${NC} (${PROC_NAME}) has suspicious library loaded:\n"
            echo "$SUSPICIOUS" | while read lib; do
                if [ -n "$lib" ]; then
                    printf "  ${RED}$lib${NC}\n"
                    FOUND_LOADED=1
                fi
            done
        fi
    fi
done
if [ $FOUND_LOADED -eq 0 ]; then
    printf "${GREEN}[OK]${NC} No suspicious libraries currently loaded in processes.\n"
fi

# 10. Summary and remediation
printf "\n${BLUE}========================================${NC}\n"
printf "${BLUE}Scan Complete - Remediation Steps${NC}\n"
printf "${BLUE}========================================${NC}\n\n"

printf "${YELLOW}[REMEDIATION]${NC} If threats were detected:\n"
printf "  1. Clear /etc/ld.so.preload: echo '' > /etc/ld.so.preload\n"
printf "  2. Unset LD_PRELOAD: unset LD_PRELOAD\n"
printf "  3. Remove suspicious .so files found above\n"
printf "  4. Kill suspicious processes\n"
printf "  5. Remove malicious kernel modules: rmmod <module_name>\n"
printf "  6. Check for persistence mechanisms (cron, systemd, rc.local, /etc/modules)\n"
printf "  7. Restore system binaries from known-good sources\n"
printf "  8. Run integrity checkers (AIDE, Tripwire, rkhunter)\n\n"
printf "\n${GREEN}[DONE]${NC} LD_PRELOAD rootkit scan completed.\n"