#!/bin/sh
# KaliPatriot | TTU CCDC | Landon Byrge

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

if command -v sockstat >/dev/null ; then
    LIST_CMD="sockstat -l"
    ESTB_CMD="sockstat -46c"
elif command -v ss >/dev/null ; then
    LIST_CMD="ss -blunt -p"
    ESTB_CMD="ss -buntp"
elif command -v netstat >/dev/null ; then
    LIST_CMD="netstat -tulpn"
    ESTB_CMD="netstat -tupwn"
fi

if [ -z "$LIST_CMD" ]; then
    echo "No netstat, sockstat or ss found"
    exit 1
fi

echo "${GREEN}[+] Listening Connections${NC}"
echo "${CYAN}========================================${NC}"
$LIST_CMD

echo ""
echo "${GREEN}[+] Established Connections${NC}"
echo "${CYAN}========================================${NC}"
$ESTB_CMD