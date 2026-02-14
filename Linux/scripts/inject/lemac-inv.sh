#!/bin/sh
# Lightweight Host Information Script
# Extracts only the HOST INFORMATION block from inventory.sh

IS_RHEL=false
IS_DEBIAN=false
IS_ALPINE=false
IS_SLACK=false
IS_BSD=false
IS_SUSE=false
IS_ARCH=false

ORAG='\033[0;33m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

if echo -e "test" | grep -qE '\-e'; then
    ECHO='echo'
else
    ECHO='echo -e'
fi

if [ -z "$DEBUG" ]; then
    DPRINT() { 
        "$@" 2>/dev/null 
    }
else
    DPRINT() { 
        "$@" 
    }
fi

RHEL(){
  IS_RHEL=true
}

SUSE(){
  IS_SUSE=true
}

DEBIAN(){
  IS_DEBIAN=true
}

UBUNTU(){
  DEBIAN
}

ALPINE(){
  IS_ALPINE=true
}

SLACK(){
  IS_SLACK=true
}

ARCH(){
  IS_ARCH=true
}

BSD(){
  IS_BSD=true
}

if command -v yum > /dev/null ; then
  RHEL
elif command -v zypper > /dev/null ; then
  SUSE
elif command -v apt-get > /dev/null ; then
  if $( cat /etc/os-release | grep -qi Ubuntu ); then
      UBUNTU
  else
      DEBIAN
  fi
elif command -v apk > /dev/null ; then
  ALPINE
elif command -v slapt-get > /dev/null || ( cat /etc/os-release | grep -i slackware ) ; then
  SLACK
elif command -v pacman > /dev/null ; then
  ARCH
elif command -v pkg > /dev/null || command -v pkg_info > /dev/null; then
    BSD
fi

check_domain(){
    # Check standard AD join methods
    if command -v realm > /dev/null 2>&1; then
        R_DOMAIN=$(realm list 2>/dev/null | grep 'domain-name:' | awk '{print $2}')
        if [ -n "$R_DOMAIN" ]; then
            echo "Joined to Realm: $R_DOMAIN"
            return
        fi
    fi

    if command -v wbinfo > /dev/null 2>&1; then
        W_DOMAIN=$(wbinfo --own-domain 2>/dev/null)
        if [ -n "$W_DOMAIN" ]; then
            echo "Joined to Winbind Domain: $W_DOMAIN"
            return
        fi
    fi
    
    # Check for PBIS/PowerBroker
    if [ -f /opt/pbis/bin/config ]; then
         P_DOMAIN=$(/opt/pbis/bin/config Domain 2>/dev/null)
         if [ -n "$P_DOMAIN" ]; then
             echo "Joined to PBIS Domain: $P_DOMAIN"
             return
         fi
    fi

    # Hints of domain via DNS/Hostname
    DNS_DOMAIN=$(hostname -d 2>/dev/null)
    if [ -z "$DNS_DOMAIN" ] && [ -f /etc/resolv.conf ]; then
        DNS_DOMAIN=$(grep '^domain' /etc/resolv.conf | awk '{print $2}' | head -n1)
    fi
    
    if [ -n "$DNS_DOMAIN" ]; then
        echo "DNS Domain: $DNS_DOMAIN (Join Status Unknown)"
    else
        echo "No Domain Detected"
    fi
}

${ECHO} "\n${GREEN}#############HOST INFORMATION############${NC}"

HOST=$( DPRINT hostname || DPRINT cat /etc/hostname )
DOMAIN=$(check_domain)
OS=$( cat /etc/*-release  | grep PRETTY_NAME | sed 's/PRETTY_NAME=//' | sed 's/"//g' )
if command -v 'ip' > /dev/null ; then
    IP=$( DPRINT ip a | grep -oE '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}/[[:digit:]]{1,2}' | grep -v '127.0.0.1' )
    GATEWAY=$( DPRINT ip route | grep default | awk '{print $3}' )
    MAC=$( DPRINT ip a | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' )
elif command -v 'ifconfig' > /dev/null ; then 
    if [ $IS_BSD = true ]; then
        IP=$( DPRINT ifconfig | grep -oE 'inet.+([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | grep -v '127.0.0.1' | awk '{print $2}' )
        GATEWAY=$( DPRINT netstat -rn | grep default | awk '{print $2}' )
        MAC=$( DPRINT ifconfig | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' )
    else
        IP=$( DPRINT ifconfig | grep -oE 'inet.+([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | grep -v '127.0.0.1' )
        GATEWAY=$( DPRINT route -n | grep 'UG' | awk '{print $2}' )
        MAC=$( DPRINT ifconfig | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' )
    fi
else
    IP="ip a and ifconfig command not found"
    GATEWAY="ip route and route command not found"
    MAC="ifconfig command not found"
fi
RAM=$( DPRINT free -h --si | grep Mem | awk '{print $2}' )
if [ -z "$RAM" ]; then
    RAM=$( sysctl -n hw.realmem | awk '{ byte =$1 /1024/1024/1024; print byte " GB" }' )
fi
STORAGE=$( DPRINT df -h | grep -E '\s/\s*$' | awk '{print $2}' )

${ECHO} "${BLUE}[+] Hostname:${NC} $HOST"
${ECHO} "${BLUE}[+] Domain:${NC} $DOMAIN"
${ECHO} "${BLUE}[+] OS:${NC} $OS"
${ECHO} "${BLUE}[+] RAM:${NC} $RAM"
${ECHO} "${BLUE}[+] Storage:${NC} $STORAGE"
${ECHO} "${BLUE}[+] IP Addresses and interfaces:${NC} $IP"
${ECHO} "${BLUE}[+] Gateway:${NC} $GATEWAY\n"
${ECHO} "${BLUE}[+] MAC Addresses:${NC} $MAC\n"
