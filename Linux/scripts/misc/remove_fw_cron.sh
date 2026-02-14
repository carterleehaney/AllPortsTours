#!/bin/sh
# Remove the safety firewall-flush cronjob installed by apply_fw_DANGER.sh
# Run this AFTER you've confirmed you are NOT locked out.

MARKER="COORD_FW_SAFETY_FLUSH"

CURRENT=$(crontab -l 2>/dev/null)

if echo "$CURRENT" | grep -q "$MARKER"; then
    echo "$CURRENT" | grep -v "$MARKER" | crontab -
    echo "[+] Safety firewall-flush cronjob removed."
else
    echo "[*] No safety firewall-flush cronjob found. Nothing to remove."
fi

# Verify
if crontab -l 2>/dev/null | grep -q "$MARKER"; then
    echo "[-] ERROR: Cronjob still present. Manual removal required:"
    echo "    Run 'crontab -e' and delete the line containing $MARKER"
else
    echo "[+] Verified: cronjob is gone."
fi
