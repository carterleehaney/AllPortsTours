#!/bin/sh
# thanks @d_tranman/Nigel Gerald/Nigerald
# KaliPatriot was here, but can someone tell me what the hell is going on here?
# Foister is just happy to be here

ipt=$(command -v iptables || command -v /sbin/iptables || command -v /usr/sbin/iptables)
IS_BSD=false

if command -v pkg >/dev/null || command -v pkg_info >/dev/null; then
    IS_BSD=true
fi

ALLOW() {
    if [ "$IS_BSD" = true ]; then
        pfctl -d
        pfctl -F all
    else
        $ipt -P INPUT ACCEPT; $ipt -P OUTPUT ACCEPT ; $ipt -P FORWARD ACCEPT ; $ipt -F; $ipt -X
    fi
}

CHECKERR() {
    if [ ! $? -eq 0 ]; then
        echo "ERROR, EXITTING TO PREVENT LOCKOUT"
        ALLOW
        exit 1
    fi
}

if [ -z "$ipt" ] && [ "$IS_BSD" = false ]; then
    echo "NO IPTABLES ON THIS SYSTEM, NOT BSD, GOOD LUCK"
    exit 1
fi

if [ -z "$DISPATCHER" ]; then
    echo "DISPATCHER not defined."
    exit 1
fi

if [ -z "$LOCALNETWORK" ]; then
    echo "LOCALNETWORK not defined."
    exit 1
fi

if [ -z "$CCSHOST" ] && [ -z "$NOTNATS" ]; then
    echo "CCSHOST not defined and WE ARE AT NATS BRO!"
    exit 1
fi

if [ -z "$BCK" ]; then
    BCK="/root/.cache"
else 
    mkdir -p $BCK 2>/dev/null
fi

if [ -f /etc/ufw/ufw.conf ]; then
    ufw disable
fi

if [ -f /etc/firewalld/firewalld.conf ]; then
    systemctl stop firewalld
    systemctl disable firewalld
fi

FW_FLUSH_COMMENT="# COORD_FW_SAFETY_FLUSH"
if [ "$IS_BSD" = true ]; then
    FW_FLUSH_CMD="pfctl -d; pfctl -F all $FW_FLUSH_COMMENT"
else
    FW_FLUSH_CMD="$ipt -P INPUT ACCEPT; $ipt -P OUTPUT ACCEPT; $ipt -P FORWARD ACCEPT; $ipt -F; $ipt -X $FW_FLUSH_COMMENT"
fi

# Remove any existing safety flush cron before adding a fresh one
( crontab -l 2>/dev/null | grep -v "COORD_FW_SAFETY_FLUSH" ; echo "*/5 * * * * $FW_FLUSH_CMD" ) | crontab -
echo "[!] SAFETY CRON INSTALLED: Firewall will be flushed every 5 minutes."
echo "[!] Run misc/remove_fw_cron.sh once connectivity is confirmed."

if [ ! -z "$ipt" ]; then
    iptables-save > /opt/rules.v4
    iptables-save > $BCK/rules.v4.old

    ALLOW

    #$ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    #$ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    if [ -n "$CCSHOST" ]; then
        $ipt -A OUTPUT -d $CCSHOST -j ACCEPT
        CHECKERR
        $ipt -A INPUT -s $CCSHOST -j ACCEPT
        CHECKERR
    fi

    # Allow local network
    $ipt -A INPUT -s $LOCALNETWORK -j ACCEPT
    CHECKERR
    $ipt -A OUTPUT -d $LOCALNETWORK -j ACCEPT
    CHECKERR

    # Allow loopback
    $ipt -A INPUT -i lo -j ACCEPT
    CHECKERR
    $ipt -A OUTPUT -o lo -j ACCEPT
    CHECKERR

    # Allow in SSH from dispatcher
    $ipt -A INPUT -s $DISPATCHER -p tcp --dport 22 -j ACCEPT
    CHECKERR
    $ipt -A OUTPUT -d $DISPATCHER -p tcp --sport 22 -j ACCEPT
    CHECKERR

#    MYIP=$(hostname -I 2>/dev/null | awk '{print $1}')
#    if [ -z "$MYIP" ]; then
#        MYIP=$(ip -4 -o addr show 2>/dev/null | awk '!/127\.0\.0\.1/ {gsub(/\/.*/, "", $4); print $4; exit}')
#    fi
#    if [ -z "$MYIP" ]; then
#        MYIP=$(ifconfig 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ {gsub(/addr:/, "", $2); print $2; exit}')
#    fi
#    case "$MYIP" in
#        10.10.20.101)
#            $ipt -A INPUT -s 8.8.8.8 -p tcp --dport 22 -j ACCEPT
#            ;;
#        10.10.20.103)
#            $ipt -A INPUT -s 10.10.10.10 -p tcp --dport 22 -j ACCEPT
#            ;;
#        *)
#            echo "[*] Rules for $MYIP"
#            ;;
#    esac

    # Block everything else
    $ipt -P INPUT DROP
    CHECKERR
    $ipt -P OUTPUT DROP
    CHECKERR
    $ipt -P FORWARD DROP
    CHECKERR

    # Save rules
    iptables-save > /opt/rules.v4
    iptables-save > $BCK/rules.v4
    iptables-save
elif [ "$IS_BSD" = true ]; then
    ALLOW

    mv /etc/pf.conf "$BCK/pf.conf.old"

    echo "set skip on lo" > /etc/pf.conf

    for i in $(echo "$DISPATCHER" | tr ',' ' '); do
        echo "pass in quick proto tcp from $i to any port 22" >> /etc/pf.conf
    done

    for i in $(echo "$LOCALNETWORK" | tr ',' ' '); do
        echo "pass in quick from $i to any" >> /etc/pf.conf
        echo "pass out quick from any to $i" >> /etc/pf.conf
    done

    for i in $(echo "$CCSHOST" | tr ',' ' '); do
        echo "pass out quick from any to $i" >> /etc/pf.conf
        echo "pass in quick from $i to any" >> /etc/pf.conf
    done

#    # (BSD)
#    MYIP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
#    case "$MYIP" in
#        10.250.72.10)
#            ;;
#        10.250.72.11)
#            ;;
#        10.250.72.12)
#            ;;
#        10.250.72.13)
#            ;;
#        *)
#            echo "[*] Rules for $MYIP"
#            ;;
#    esac

    echo "block all" >> /etc/pf.conf

    cat /etc/pf.conf

    kldload pf
    pfctl -f /etc/pf.conf
    cat /etc/pf.conf
    pfctl -e
fi