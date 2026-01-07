#!/bin/sh
Script="/bin/sh"
echo "REDTRAP $(date +%H%M%S) -- $0 $@" >> /var/log/commands
r1(){
echo -n root@HOSTNAME:~# "$1"; if [ -n "$1" ]; then
echo "$1: command not found"
echo "REDTRAP $(date +%H%M%S) -- $1" >> /var/log/commands
fi; r1
}

trap "r1" SIGINT SIGISTP exit; r1
exit"

echo "$Script" > /bin/red
chmod +x /bin/red