#!/bin/sh

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print header
print_header() {
    echo ""
    echo "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}  ${BOLD}${MAGENTA}SSH Authentication Log Analysis${NC}                               ${CYAN}║${NC}"
    echo "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Print section divider
print_divider() {
    echo "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

# Analyze log file
analyze_log() {
    logfile=$1
    
    if [ -f "$logfile" ]; then
        # All display output goes to stderr (>&2)
        echo "" >&2
        echo "${BOLD}${YELLOW} Analyzing: ${NC}${CYAN}$logfile${NC}" >&2
        print_divider >&2
        
        # Count failed passwords
        failed=$(grep 'Failed password' "$logfile" 2>/dev/null | wc -l)
        
        # Count accepted passwords
        accepted=$(grep 'Accepted password' "$logfile" 2>/dev/null | wc -l)
        accepted_key=$(grep 'Accepted publickey' "$logfile" 2>/dev/null | wc -l)
        
        # Display results
        if [ "$failed" -gt 0 ]; then
            echo "${RED}  ✗ Failed Password Attempts:${NC}  ${BOLD}$failed${NC}" >&2
        else
            echo "${GREEN}  ✓ Failed Password Attempts:${NC}  ${BOLD}0${NC}" >&2
        fi
        
        if [ "$accepted" -gt 0 ]; then
            echo "${GREEN}  ✓ Accepted Passwords:${NC}        ${BOLD}$accepted${NC}" >&2
        else
            echo "  ○ Accepted Passwords:        ${BOLD}0${NC}" >&2
        fi
        
        if [ "$accepted_key" -gt 0 ]; then
            echo "${GREEN}  ✓ Accepted Public Keys:${NC}      ${BOLD}$accepted_key${NC}" >&2
        else
            echo "  ○ Accepted Public Keys:      ${BOLD}0${NC}" >&2
        fi
        
        # Calculate total
        total=$((failed + accepted + accepted_key))
        echo "${BLUE}  ═ Total Auth Events:${NC}         ${BOLD}$total${NC}" >&2
        
        # Show detailed info if there are failed attempts
        if [ "$failed" -gt 0 ]; then
            echo "" >&2
            echo "${BOLD}${MAGENTA}  Top Attacking IPs:${NC}" >&2
            grep 'Failed password' "$logfile" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -5 | while read count ip; do
                echo "${RED}    • $ip${NC} - ${BOLD}$count${NC} attempts" >&2
            done
            
            echo "" >&2
            echo "${BOLD}${MAGENTA}  Top Targeted Usernames:${NC}" >&2
            grep 'Failed password for' "$logfile" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}' | sort | uniq -c | sort -rn | head -5 | while read count user; do
                echo "${YELLOW}    • $user${NC} - ${BOLD}$count${NC} attempts" >&2
            done
            
            echo "" >&2
            echo "${BOLD}${MAGENTA}  Recent Failed Attempts (last 5):${NC}" >&2
            grep 'Failed password' "$logfile" 2>/dev/null | tail -5 | while read line; do
                timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
                user=$(echo "$line" | grep -oP 'for (invalid user )?\K\S+' | head -1)
                ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
                echo "${CYAN}    $timestamp${NC} - User: ${YELLOW}$user${NC} from ${RED}$ip${NC}" >&2
            done
        fi
        
        # Return values for summary (only this goes to stdout)
        echo "$failed $accepted $accepted_key"
    else
        # Return zeros if file doesn't exist
        echo "0 0 0"
    fi
}

# Main execution
print_header

total_failed=0
total_accepted=0
total_keys=0
logs_found=0

# Check /var/log/secure (RHEL/CentOS)
if [ -f /var/log/secure ]; then
    result=$(analyze_log "/var/log/secure")
    total_failed=$((total_failed + $(echo $result | cut -d' ' -f1)))
    total_accepted=$((total_accepted + $(echo $result | cut -d' ' -f2)))
    total_keys=$((total_keys + $(echo $result | cut -d' ' -f3)))
    logs_found=$((logs_found + 1))
fi

# Check /var/log/auth.log (Debian/Ubuntu)
if [ -f /var/log/auth.log ]; then
    result=$(analyze_log "/var/log/auth.log")
    total_failed=$((total_failed + $(echo $result | cut -d' ' -f1)))
    total_accepted=$((total_accepted + $(echo $result | cut -d' ' -f2)))
    total_keys=$((total_keys + $(echo $result | cut -d' ' -f3)))
    logs_found=$((logs_found + 1))
fi

# Check /var/log/messages
if [ -f /var/log/messages ]; then
    result=$(analyze_log "/var/log/messages")
    total_failed=$((total_failed + $(echo $result | cut -d' ' -f1)))
    total_accepted=$((total_accepted + $(echo $result | cut -d' ' -f2)))
    total_keys=$((total_keys + $(echo $result | cut -d' ' -f3)))
    logs_found=$((logs_found + 1))
fi

# Print summary if logs were found
if [ $logs_found -gt 0 ]; then
    echo ""
    echo "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}  ${BOLD}${MAGENTA}Summary Statistics${NC}"
    echo "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    
    if [ $total_failed -gt 0 ]; then
        echo "${CYAN}║${NC}  ${RED}Total Failed Attempts:${NC}      ${BOLD}${RED}$total_failed${NC}"
    else
        echo "${CYAN}║${NC}  ${GREEN}Total Failed Attempts:${NC}      ${BOLD}${GREEN}$total_failed${NC}"
    fi
    
    echo "${CYAN}║${NC}  ${GREEN}Total Accepted Passwords:${NC}   ${BOLD}$total_accepted${NC}"
    echo "${CYAN}║${NC}  ${GREEN}Total Accepted Keys:${NC}        ${BOLD}$total_keys${NC}"
    echo "${CYAN}║${NC}  ${BLUE}Total Logs Analyzed:${NC}        ${BOLD}$logs_found${NC}"
    echo "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
else
    echo ""
    echo "${YELLOW}⚠  No authentication log files found!${NC}"
    echo ""
fi