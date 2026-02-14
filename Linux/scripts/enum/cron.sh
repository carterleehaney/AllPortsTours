#!/bin/bash
# Cron Enumeration - All User Crontabs

echo "=== User Crontabs ==="
while IFS=: read -r user _ _ _ _ _ _; do
    cron=$(crontab -u "$user" -l 2>/dev/null | grep -v '^#')
    if [ -n "$cron" ]; then
        echo "[$user]"
        echo "$cron"
    fi
done < /etc/passwd