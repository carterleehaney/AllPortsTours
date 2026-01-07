#!/bin/sh

# Default to normal commands
CMD_ECHO="echo"
CMD_LS="ls"
CMD_CAT="cat"

# Check for busybox and override if available
if command -v busybox >/dev/null 2>&1; then
    echo "[INFO] BusyBox found, using it for commands."
    CMD_ECHO="busybox echo"
    CMD_LS="busybox ls"
    CMD_CAT="busybox cat"
else
    echo "[INFO] BusyBox not found, falling back to standard commands."
fi

$CMD_ECHO "Current LD_PRELOAD: $LD_PRELOAD"
$CMD_LS -al /etc/ld.so.preload 2>/dev/null
$CMD_CAT /etc/ld.so.preload 2>/dev/null

# Clear the preload file safely
$CMD_ECHO "" > /etc/ld.so.preload