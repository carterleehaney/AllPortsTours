#!/bin/bash
# NightWalk3r | TTU CCDC | Behnjamin Barlow


# bashrc.sh - Enumerate .bashrc and .profile files for SUSPICIOUS configurations
# Must be run as root to access all user files
# Focuses on malicious patterns, not common legitimate usage

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Suspicious patterns to search for (regex patterns)
# These are balanced to catch threats while avoiding common false positives
declare -A PATTERNS=(
    ["Remote Execution"]="(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh)"
    ["Inline Scripts"]="(python|perl|ruby)[[:space:]]+-[ce][[:space:]]"
    ["Suspicious Paths"]="(^|[[:space:]])/tmp/[^[:space:]]+\.(sh|py|pl|rb|elf)|(^|[[:space:]])/dev/shm/[^[:space:]]+\.(sh|py|pl)"
    ["Executable Invocation"]="^[[:space:]]*/[a-zA-Z0-9/_.-]+\.(sh|py|pl|rb|bin|elf)"
    ["Base64 Decode"]="base64[[:space:]].*-d.*\|"
    ["Background Process"]="nohup[[:space:]].*&"
    ["Chmod 777"]="chmod[[:space:]]+777"
    ["Chmod SetUID"]="chmod[[:space:]]+[0-9]*[4-7][0-9][0-9]"
    ["SSH Key"]="(ssh-rsa|ssh-ed25519)[[:space:]]+AAAA"
)

# Counter for findings
TOTAL_FINDINGS=0
FILES_WITH_ISSUES=0

# Banner
echo -e "${BOLD}${CYAN}========================================${NC}"
echo -e "${BOLD}${CYAN}  Bashrc & Profile Enumeration Script${NC}"
echo -e "${BOLD}${CYAN}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] This script must be run as root${NC}"
    exit 1
fi

# Function to analyze a file for suspicious patterns
analyze_file() {
    local file="$1"
    local user="$2"
    local found=0
    local file_findings=0
    
    if [ ! -f "$file" ]; then
        return
    fi
    
    # Check if file is readable
    if [ ! -r "$file" ]; then
        echo -e "${RED}[!] Cannot read: $file${NC}"
        return
    fi
    
    # Get file permissions and modification time
    local perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)
    local mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" "$file" 2>/dev/null)
    
    # Search for suspicious patterns
    for pattern_name in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$pattern_name]}"
        
        local match_count=$(grep -Eic "$pattern" "$file" 2>/dev/null)
        # Strip whitespace and ensure it's a number
        match_count=$(echo "$match_count" | tr -d '[:space:]')
        [[ ! "$match_count" =~ ^[0-9]+$ ]] && match_count=0
        
        if [ "$match_count" -gt 0 ] 2>/dev/null; then
            if [ $found -eq 0 ]; then
                found=1
                ((FILES_WITH_ISSUES++))
            fi
            
            # Show each match on a single compact line, excluding comments and aliases
            grep -Ein "$pattern" "$file" 2>/dev/null | while IFS=: read -r line_num line_content; do
                # Trim leading/trailing whitespace from content
                line_content=$(echo "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                # Skip if line starts with # (comment) or alias (to avoid false positives)
                if [[ "$line_content" =~ ^# ]] || [[ "$line_content" =~ ^alias[[:space:]] ]]; then
                    continue
                fi
                
                echo -e "${RED}[!]${NC} ${file} ${BLUE}[$user/$perms/$mtime]${NC} ${MAGENTA}[$pattern_name]${NC} L${line_num}: ${line_content}"
            done
        fi
    done
    
    # Also check for unusual aliases, functions, and exports (summary only)
    local alias_count=$(grep -c "^[[:space:]]*alias" "$file" 2>/dev/null)
    local function_count=$(grep -Ec "^[[:space:]]*(function |[a-zA-Z_][a-zA-Z0-9_]*\(\))" "$file" 2>/dev/null)
    local export_count=$(grep -c "^[[:space:]]*export" "$file" 2>/dev/null)
    
    # Strip whitespace and ensure they're numbers
    alias_count=$(echo "$alias_count" | tr -d '[:space:]')
    function_count=$(echo "$function_count" | tr -d '[:space:]')
    export_count=$(echo "$export_count" | tr -d '[:space:]')
    
    [[ ! "$alias_count" =~ ^[0-9]+$ ]] && alias_count=0
    [[ ! "$function_count" =~ ^[0-9]+$ ]] && function_count=0
    [[ ! "$export_count" =~ ^[0-9]+$ ]] && export_count=0
    
    # Only report if counts are unusually high
    if [ "$alias_count" -gt 10 ] 2>/dev/null || [ "$function_count" -gt 5 ] 2>/dev/null || [ "$export_count" -gt 20 ] 2>/dev/null; then
        echo -e "${YELLOW}[?]${NC} ${file} ${BLUE}[$user/$perms]${NC} High counts - Aliases:$alias_count Functions:$function_count Exports:$export_count"
        if [ $found -eq 0 ]; then
            found=1
            ((FILES_WITH_ISSUES++))
        fi
    fi
    
    if [ $found -eq 1 ]; then
        ((TOTAL_FINDINGS++))
    fi
}

# Check root's files
echo -e "${BOLD}${BLUE}[*] Checking root user files...${NC}"
echo ""
analyze_file "/root/.bashrc" "root"
analyze_file "/root/.profile" "root"
analyze_file "/root/.bash_profile" "root"
analyze_file "/root/.bash_aliases" "root"
analyze_file "/root/.zshrc" "root"

# Get all users from /etc/passwd
echo -e "${BOLD}${BLUE}[*] Checking all user files...${NC}"
echo ""

while IFS=: read -r username _ uid _ _ homedir shell; do
    # Skip system users (UID < 1000) except root which we already checked
    if [ "$uid" -lt 1000 ] && [ "$username" != "root" ]; then
        continue
    fi
    
    # Skip root since we already checked it
    if [ "$username" = "root" ]; then
        continue
    fi
    
    # Skip users with no valid shell
    if [[ "$shell" == *"nologin"* ]] || [[ "$shell" == *"false"* ]]; then
        continue
    fi
    
    # Check if home directory exists
    if [ ! -d "$homedir" ]; then
        continue
    fi
    
    # Analyze common shell configuration files
    analyze_file "$homedir/.bashrc" "$username"
    analyze_file "$homedir/.profile" "$username"
    analyze_file "$homedir/.bash_profile" "$username"
    analyze_file "$homedir/.bash_aliases" "$username"
    analyze_file "$homedir/.zshrc" "$username"
    
done < /etc/passwd

# Summary
echo -e "${BOLD}${GREEN}========================================${NC}"
echo -e "${BOLD}${GREEN}  Summary${NC}"
echo -e "${BOLD}${GREEN}========================================${NC}"
echo -e "${CYAN}Files with suspicious patterns:${NC} $FILES_WITH_ISSUES"
echo -e "${CYAN}Total suspicious findings:${NC} $TOTAL_FINDINGS"
echo ""
echo -e "${BOLD}${GREEN}[✓] Enumeration complete!${NC}"
echo ""