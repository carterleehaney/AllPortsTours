#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# KaliPatriot | TTU CCDC | Landon Byrge
# 7oister | TTU CCDC | Landon Foister

IS_RHEL=false
IS_DEBIAN=false
IS_ALPINE=false
IS_SLACK=false
IS_BSD=false
IS_FREEBSD=false
IS_OPENBSD=false
IS_SUSE=false
IS_ARCH=false

ORAG=''
GREEN=''
YELLOW=''
BLUE=''
RED=''
NC=''

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

FREEBSD(){
  IS_BSD=true
  IS_FREEBSD=true
}

OPENBSD(){
  IS_BSD=true
  IS_OPENBSD=true
}


if command -v yum >/dev/null ; then
  RHEL
elif command -v zypper >/dev/null ; then
  SUSE
elif command -v apt-get >/dev/null ; then
  if [ -f /etc/os-release ] && cat /etc/os-release | grep -qi Ubuntu; then
      UBUNTU
  else
      DEBIAN
  fi
elif command -v apk >/dev/null ; then
  ALPINE
elif command -v slapt-get >/dev/null || ( [ -f /etc/os-release ] && cat /etc/os-release | grep -qi slackware ) ; then
  SLACK
elif command -v pacman >/dev/null ; then
  ARCH
elif command -v pkg_add >/dev/null && uname -s 2>/dev/null | grep -qi openbsd; then
  OPENBSD
elif command -v pkg >/dev/null || command -v pkg_info >/dev/null; then
  FREEBSD
fi

if [ -n "$COLOR" ]; then
    ORAG='\033[0;33m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
fi

check_domain(){
    # Check standard AD join methods
    if command -v realm >/dev/null 2>&1; then
        R_DOMAIN=$(realm list 2>/dev/null | grep 'domain-name:' | awk '{print $2}')
        if [ -n "$R_DOMAIN" ]; then
            echo "Joined to Realm: $R_DOMAIN"
            return
        fi
    fi

    if command -v wbinfo >/dev/null 2>&1; then
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

${ECHO} "${GREEN}
##################################
#                                #
#         INVENTORY TIME         #
#                                #
##################################
${NC}\n"

${ECHO} "\n${GREEN}#############HOST INFORMATION############${NC}\n"

HOST=$( DPRINT hostname || DPRINT cat /etc/hostname )
DOMAIN=$(check_domain)
OS=$( cat /etc/*-release 2>/dev/null | grep PRETTY_NAME | sed 's/PRETTY_NAME=//' | sed 's/"//g' )
if [ -z "$OS" ]; then
    OS=$( uname -sr 2>/dev/null )
fi
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
    if [ $IS_OPENBSD = true ]; then
        RAM=$( sysctl -n hw.physmem 2>/dev/null | awk '{ byte = $1 /1024/1024/1024; printf "%.1f GB", byte }' )
    else
        RAM=$( sysctl -n hw.realmem 2>/dev/null | awk '{ byte = $1 /1024/1024/1024; printf "%.1f GB", byte }' )
    fi
fi
STORAGE=$( DPRINT df -h | grep -E '\s/\s*$' | awk '{print $2}' )
USERS=$( cat /etc/passwd | grep -vE '(false|nologin|sync)$' | grep -E '/.*sh$' )
SUDOERS=$( DPRINT cat /etc/sudoers /etc/sudoers.d/* | grep -vE '#|Defaults|^\s*$' | grep -vE '(Cmnd_Alias|\\)' )
NOAUTHSUDOERS=$( DPRINT cat /etc/sudoers /etc/sudoers.d/* | grep -E '^\s*Defaults\s+[^\s]authenticate' )
SUIDS=$(find /bin /sbin /usr -perm -u=g+s -type f -exec ls -la {} \; | grep -E '(s7z|aa-exec|ab|agetty|alpine|ansible-playbook|ansible-test|aoss|apt|apt-get|ar|aria2c|arj|arp|as|ascii85|ascii-xfr|ash|aspell|at|atobm|awk|aws|base32|base58|base64|basenc|basez|bash|batcat|bc|bconsole|bpftrace|bridge|bundle|bundler|busctl|busybox|byebug|bzip2|c89|c99|cabal|cancel|capsh|cat|cdist|certbot|check_by_ssh|check_cups|check_log|check_memory|check_raid|check_ssl_cert|check_statusfile|chmod|choom|chown|chroot|clamscan|cmp|cobc|column|comm|composer|cowsay|cowthink|cp|cpan|cpio|cpulimit|crash|crontab|csh|csplit|csvtool|cupsfilter|curl|cut|dash|date|dd|debugfs|dialog|diff|dig|distcc|dmesg|dmidecode|dmsetup|dnf|docker|dos2unix|dosbox|dotnet|dpkg|dstat|dvips|easy_install|eb|ed|efax|elvish|emacs|enscript|env|eqn|espeak|ex|exiftool|expand|expect|facter|file|find|finger|fish|flock|fmt|fold|fping|ftp|gawk|gcc|gcloud|gcore|gdb|gem|genie|genisoimage|ghc|ghci|gimp|ginsh|git|grc|grep|gtester|gzip|hd|head|hexdump|highlight|hping3|iconv|iftop|install|ionice|ip|irb|ispell|jjs|joe|join|journalctl|jq|jrunscript|jtag|julia|knife|ksh|ksshell|ksu|kubectl|latex|latexmk|ldconfig|ld.so|less|lftp|ln|loginctl|logsave|look|lp|ltrace|lua|lualatex|luatex|lwp-download|lwp-request|mail|make|man|mawk|minicom|more|mosquitto|msfconsole|msgattrib|msgcat|msgconv|msgfilter|msgmerge|msguniq|mtr|multitime|mv|mysql|nano|nasm|nawk|nc|ncftp|neofetch|nft|nice|nl|nm|nmap|node|nohup|npm|nroff|nsenter|octave|od|openssl|openvpn|openvt|opkg|pandoc|paste|pax|pdb|pdflatex|pdftex|perf|perl|perlbug|pexec|pg|php|pic|pico|pidstat|pip|pkexec|pkg|posh|pr|pry|psftp|psql|ptx|puppet|pwsh|python|rake|rc|readelf|red|redcarpet|redis|restic|rev|rlogin|rlwrap|rpm|rpmdb|rpmquery|rpmverify|rsync|rtorrent|ruby|run-mailcap|run-parts|runscript|rview|rvim|sash|scanmem|scp|screen|script|scrot|sed|service|setarch|setfacl|setlock|sftp|sg|shuf|slsh|smbclient|snap|socat|socket|soelim|softlimit|sort|split|sqlite3|sqlmap|ss|ssh|ssh-agent|ssh-keygen|ssh-keyscan|sshpass|start-stop-daemon|stdbuf|strace|strings|sysctl|systemctl|systemd-resolve|tac|tail|tar|task|taskset|tasksh|tbl|tclsh|tcpdump|tdbtool|tee|telnet|terraform|tex|tftp|tic|time|timedatectl|timeout|tmate|tmux|top|torify|torsocks|troff|tshark|ul|unexpand|uniq|unshare|unsquashfs|unzip|update-alternatives|uudecode|uuencode|vagrant|valgrind|vi|view|vigr|vim|vimdiff|vipw|virsh|volatility|w3m|wall|watch|wc|wget|whiptail|whois|wireshark|wish|xargs|xdg-user-dir|xdotool|xelatex|xetex|xmodmap|xmore|xpad|xxd|xz|yarn|yash|yelp|yum|zathura|zip|zsh|zsoelim|zypper)$')
WORLDWRITEABLES=$( DPRINT find /usr /bin/ /sbin /var/www /lib -perm -o=w -type f -exec ls {} -la \; )
SUDOGROUP_LINES=$(grep -E "^(sudo|wheel|root):" /etc/group | sed 's/x:.*:/ /')

${ECHO} "${BLUE}[+] Hostname:${NC} $HOST"
${ECHO} "${BLUE}[+] Domain:${NC} $DOMAIN"
${ECHO} "${BLUE}[+] OS:${NC} $OS"
${ECHO} "${BLUE}[+] RAM:${NC} $RAM"
${ECHO} "${BLUE}[+] Storage:${NC} $STORAGE"
${ECHO} "${BLUE}[+] IP Addresses and interfaces${NC}"
${ECHO} "$IP"
${ECHO} "${BLUE}[+] Gateway:${NC} $GATEWAY\n"
${ECHO} "${BLUE}[+] MAC Addresses:${NC} $MAC\n"
${ECHO} "${GREEN}#############Listening Ports############${NC}"
echo ""
if command -v sockstat >/dev/null; then
    DPRINT sockstat -l | tail -n +3 | grep 'tcp\|udp' | awk '{print $1 " " $2 " " $6 }' | DPRINT column -t
elif [ $IS_OPENBSD = true ] && command -v netstat >/dev/null; then
    DPRINT netstat -an -f inet | grep 'LISTEN' | DPRINT column -t
elif command -v netstat >/dev/null && [ $IS_BSD = false ]; then
    DPRINT netstat -tlpn | tail -n +3 | awk '{print $1 " " $4 " " $6 " " $7}'| DPRINT column -t
elif command -v ss > /dev/null; then
    DPRINT ss -blunt -p | tail -n +2 | awk '{print $1 " " $5 " " $7}' | DPRINT column -t 
else
    echo "Netstat and ss commands do not exist"
fi
echo ""
${ECHO} "${GREEN}#############SERVICE INFORMATION############${NC}"
if [ $IS_ALPINE = true ]; then
    SERVICES=$( rc-status -s | grep started | awk '{print $1}' )
elif [ $IS_SLACK = true ]; then
    SERVICES=$( ls -la /etc/rc.d | grep rwx | awk '{print $9}' ) 
elif [ $IS_BSD = true ]; then
    SERVICES=$( cat /etc/rc.conf 2>/dev/null; cat /etc/rc.conf.d/* 2>/dev/null; cat /etc/rc.conf.local 2>/dev/null )
    SERVICES=$( echo "$SERVICES" | grep -i "_enable\|_flags" | grep -iv "=\"*NO\"*" | awk -F '_enable|_flags' '{print $1}' )
else
    SERVICES=$( DPRINT systemctl --type=service | grep active | awk '{print $1}' || service --status-all | grep -E '(+|is running)' )
fi

${ECHO} "\n${GREEN}#############SALT INFORMATION############${NC}\n"

# Check if Salt is installed
if [ -f /etc/salt/minion ] || [ -f /etc/salt/master ]; then
    if [ -f /etc/salt/minion ]; then
        ${ECHO} "${BLUE}[+] Salt Minion is installed${NC}"
        ${ECHO} "${YELLOW}Minion Config:${NC}"
        MINION_CFG=$( cat /etc/salt/minion 2>/dev/null | grep -E "^\s*[^#]" )
        ${ECHO} "${ORAG}$MINION_CFG${NC}\n"
        
        if [ -f /etc/salt/minion.d/master.conf ]; then
            ${ECHO} "${YELLOW}Master Config (minion.d):${NC}"
            ${ECHO} "${ORAG}$( cat /etc/salt/minion.d/master.conf | grep -E "^\s*[^#]" )${NC}\n"
        fi
        
        if [ -f /etc/salt/minion_id ]; then
            ${ECHO} "${YELLOW}Minion ID: $( cat /etc/salt/minion_id )${NC}\n"
        fi
    fi
    
    if [ -f /etc/salt/master ]; then
        ${ECHO} "${BLUE}[+] Salt Master is installed${NC}"
        ${ECHO} "${YELLOW}Master Config:${NC}"
        MASTER_CFG=$( cat /etc/salt/master 2>/dev/null | grep -E "^\s*[^#]" )
        ${ECHO} "${ORAG}$MASTER_CFG${NC}\n"
        
        if [ -f /etc/salt/master.d/master.conf ]; then
            ${ECHO} "${ORAG}$( cat /etc/salt/master.d/master.conf | grep -E "^\s*[^#]" )${NC}\n"
        fi
        
        # List accepted keys (minions)
        ${ECHO} "${YELLOW}Accepted Minion Keys:${NC}"
        SALT_KEYS=$( DPRINT salt-key -L 2>/dev/null )
        ${ECHO} "${ORAG}$SALT_KEYS${NC}\n"
        
        # List salt files
        if [ -d /srv/salt ]; then
            ${ECHO} "${YELLOW}Salt State Files (/srv/salt):${NC}"
            SALT_FILES=$( DPRINT ls -laR /srv/salt 2>/dev/null | head -n 50 )
            ${ECHO} "${ORAG}$SALT_FILES${NC}\n"
        fi
        
        # Check minion status
        ${ECHO} "${YELLOW}Minion Status:${NC}"
        MINION_STATUS=$( DPRINT salt-run manage.status 2>/dev/null )
        ${ECHO} "${ORAG}$MINION_STATUS${NC}\n"
    fi
else
    ${ECHO} "${YELLOW}[-] Salt not installed${NC}"
fi

${ECHO} "\n${GREEN}#############ANSIBLE INFORMATION############${NC}\n"

# Check if ansible is installed
if command -v ansible >/dev/null 2>&1; then
    ${ECHO} "${BLUE}[+] Ansible is installed${NC}"
    ANSIBLE_VERSION=$( ansible --version 2>/dev/null | head -n 1 )
    ${ECHO} "${YELLOW}Version: $ANSIBLE_VERSION${NC}\n"
    
    # Find ansible config file
    ANSIBLE_CFG=""
    if [ -f /etc/ansible/ansible.cfg ]; then
        ANSIBLE_CFG="/etc/ansible/ansible.cfg"
    elif [ -f ~/.ansible.cfg ]; then
        ANSIBLE_CFG="$HOME/.ansible.cfg"
    elif [ -f ./ansible.cfg ]; then
        ANSIBLE_CFG="./ansible.cfg"
    fi
    
    if [ -n "$ANSIBLE_CFG" ]; then
        ${ECHO} "${BLUE}[+] Ansible Config: $ANSIBLE_CFG${NC}"
        ANSIBLE_CFG_CONTENTS=$( grep -vE '^\s*(#|;|$)' "$ANSIBLE_CFG" 2>/dev/null )
        ${ECHO} "${ORAG}$ANSIBLE_CFG_CONTENTS${NC}\n"
    fi
    
    # Find and display inventory files
    ${ECHO} "${BLUE}[+] Ansible Inventory/Hosts${NC}"
    
    INVENTORY_LOCATIONS="/etc/ansible/hosts /etc/ansible/inventory /etc/ansible/inventory.yml /etc/ansible/inventory.yaml"
    # Also check common project locations
    INVENTORY_LOCATIONS="$INVENTORY_LOCATIONS $( DPRINT find /home /root /opt /var -name 'inventory' -o -name 'inventory.yml' -o -name 'inventory.yaml' -o -name 'hosts.yml' -o -name 'hosts.yaml' 2>/dev/null | head -n 10 )"
    
    for inv in $INVENTORY_LOCATIONS; do
        if [ -f "$inv" ]; then
            ${ECHO} "\n${YELLOW}Inventory File: $inv${NC}"
            ${ECHO} "${ORAG}$( cat "$inv" | grep -vE '^\s*(#|$)' | head -n 50 )${NC}"
        elif [ -d "$inv" ]; then
            ${ECHO} "\n${YELLOW}Inventory Directory: $inv${NC}"
            for f in "$inv"/*; do
                if [ -f "$f" ]; then
                    ${ECHO} "${YELLOW}  -> $f${NC}"
                    ${ECHO} "${ORAG}$( cat "$f" | grep -vE '^\s*(#|$)' | head -n 30 )${NC}"
                fi
            done
        fi
    done
    
    # Check authentication method
    ${ECHO} "\n${BLUE}[+] Ansible Authentication Method${NC}"
    
    # Check for SSH key auth in config
    if [ -n "$ANSIBLE_CFG" ]; then
        KEY_FILE=$( grep -iE '^\s*private_key_file' "$ANSIBLE_CFG" 2>/dev/null )
        ASK_PASS=$( grep -iE '^\s*ask_pass' "$ANSIBLE_CFG" 2>/dev/null )
        REMOTE_USER=$( grep -iE '^\s*remote_user' "$ANSIBLE_CFG" 2>/dev/null )
        
        if [ -n "$KEY_FILE" ]; then
            ${ECHO} "${YELLOW}Key Auth Configured: $KEY_FILE${NC}"
        fi
        if [ -n "$ASK_PASS" ]; then
            ${ECHO} "${YELLOW}Password Prompt: $ASK_PASS${NC}"
        fi
        if [ -n "$REMOTE_USER" ]; then
            ${ECHO} "${YELLOW}Remote User: $REMOTE_USER${NC}"
        fi
    fi
    
    # Check for vault usage (indicates password storage)
    VAULT_FILES=$( DPRINT find /etc/ansible /home /root /opt -name '*.vault' -o -name 'vault.yml' -o -name 'vault.yaml' -o -name '*vault*.yml' 2>/dev/null | head -n 5 )
    if [ -n "$VAULT_FILES" ]; then
        ${ECHO} "${YELLOW}Vault Files Found (may contain passwords):${NC}"
        ${ECHO} "${ORAG}$VAULT_FILES${NC}"
    fi
    
    # Check group_vars and host_vars for auth settings
    for vardir in /etc/ansible/group_vars /etc/ansible/host_vars; do
        if [ -d "$vardir" ]; then
            ${ECHO} "\n${YELLOW}Checking $vardir for auth settings:${NC}"
            AUTH_VARS=$( DPRINT grep -rliE 'ansible_ssh_pass|ansible_password|ansible_ssh_private_key|ansible_become_pass' "$vardir" 2>/dev/null )
            if [ -n "$AUTH_VARS" ]; then
                ${ECHO} "${RED}Files with credentials:${NC}"
                ${ECHO} "${ORAG}$AUTH_VARS${NC}"
                for f in $AUTH_VARS; do
                    ${ECHO} "${YELLOW}Contents of $f:${NC}"
                    ${ECHO} "${ORAG}$( cat "$f" | grep -vE '^\s*(#|$)' )${NC}"
                done
            fi
        fi
    done
    
    # Find playbooks
    ${ECHO} "\n${BLUE}[+] Ansible Playbooks${NC}"
    PLAYBOOK_DIRS="/etc/ansible /opt /home /root /var"
    PLAYBOOKS=$( DPRINT find $PLAYBOOK_DIRS -maxdepth 4 \( -name '*.yml' -o -name '*.yaml' \) -exec grep -l '^\s*-\s*hosts:' {} \; 2>/dev/null | head -n 20 )
    
    if [ -n "$PLAYBOOKS" ]; then
        ${ECHO} "${YELLOW}Found Playbooks:${NC}"
        for pb in $PLAYBOOKS; do
            PBNAME=$( basename "$pb" )
            PBHOSTS=$( grep -E '^\s*-?\s*hosts:' "$pb" 2>/dev/null | head -n 3 )
            ${ECHO} "${ORAG}$pb${NC}"
            ${ECHO} "  ${YELLOW}Targets: $PBHOSTS${NC}"
        done
    else
        ${ECHO} "${YELLOW}No playbooks found in common locations${NC}"
    fi
    
    # Check for ansible-pull (indicates pull-based setup)
    if command -v ansible-pull >/dev/null 2>&1; then
        PULL_CRON=$( DPRINT grep -r 'ansible-pull' /etc/cron* /var/spool/cron* 2>/dev/null )
        if [ -n "$PULL_CRON" ]; then
            ${ECHO} "\n${BLUE}[+] Ansible Pull Cron Jobs${NC}"
            ${ECHO} "${ORAG}$PULL_CRON${NC}"
        fi
    fi
    
    # Check for AWX/Tower
    if command -v awx >/dev/null 2>&1 || [ -d /var/lib/awx ]; then
        ${ECHO} "\n${BLUE}[+] AWX/Tower Detected${NC}"
    fi
else
    ${ECHO} "${YELLOW}[-] Ansible not installed${NC}"
fi

# Check if this machine is MANAGED BY Ansible (regardless of whether ansible is installed locally)
${ECHO} "\n${GREEN}#############ANSIBLE MANAGED NODE CHECK############${NC}\n"

ANSIBLE_MANAGED=false

# Check for Ansible temp/cache directories left by remote execution
ANSIBLE_TMP_DIRS=""
for homedir in /root /home/*; do
    if [ -d "$homedir/.ansible" ]; then
        ANSIBLE_TMP_DIRS="$ANSIBLE_TMP_DIRS $homedir/.ansible"
    fi
done
if [ -d /tmp/.ansible ]; then
    ANSIBLE_TMP_DIRS="$ANSIBLE_TMP_DIRS /tmp/.ansible"
fi

if [ -n "$ANSIBLE_TMP_DIRS" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Ansible temp/cache directories found (indicates remote management):${NC}"
    for d in $ANSIBLE_TMP_DIRS; do
        ${ECHO} "${ORAG}  $d${NC}"
        DPRINT ls -la "$d" 2>/dev/null | head -n 10 | while read -r line; do
            ${ECHO} "${ORAG}    $line${NC}"
        done
    done
    echo ""
fi

# Check for Ansible local facts directory
if [ -d /etc/ansible/facts.d ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Ansible local facts directory exists (/etc/ansible/facts.d):${NC}"
    FACTS_FILES=$( DPRINT ls -la /etc/ansible/facts.d/ 2>/dev/null )
    if [ -n "$FACTS_FILES" ]; then
        ${ECHO} "${ORAG}$FACTS_FILES${NC}\n"
    fi
fi

# Check authorized_keys for Ansible controller keys
ANSIBLE_KEYS=""
for keyfile in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    if [ -f "$keyfile" ]; then
        FOUND=$( grep -i 'ansible' "$keyfile" 2>/dev/null )
        if [ -n "$FOUND" ]; then
            ANSIBLE_KEYS="$ANSIBLE_KEYS\n  $keyfile:\n$FOUND"
        fi
    fi
done

if [ -n "$ANSIBLE_KEYS" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] SSH authorized_keys with Ansible references:${NC}"
    ${ECHO} "${ORAG}$ANSIBLE_KEYS${NC}\n"
fi

# Check auth logs for recent Ansible SSH connections
ANSIBLE_LOG_HITS=""
if [ -f /var/log/auth.log ]; then
    ANSIBLE_LOG_HITS=$( grep -i 'ansible' /var/log/auth.log 2>/dev/null | tail -n 10 )
elif [ -f /var/log/secure ]; then
    ANSIBLE_LOG_HITS=$( grep -i 'ansible' /var/log/secure 2>/dev/null | tail -n 10 )
fi

if [ -n "$ANSIBLE_LOG_HITS" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Recent Ansible activity in auth logs:${NC}"
    ${ECHO} "${ORAG}$ANSIBLE_LOG_HITS${NC}\n"
fi

# Check for AnsiballZ or ansible module remnants in /tmp
ANSIBLE_TMP_MODULES=$( DPRINT find /tmp -maxdepth 2 -name 'AnsiballZ_*' -o -name 'ansible-tmp-*' 2>/dev/null | head -n 10 )
if [ -n "$ANSIBLE_TMP_MODULES" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Ansible module remnants in /tmp:${NC}"
    ${ECHO} "${ORAG}$ANSIBLE_TMP_MODULES${NC}\n"
fi

# Check for ansible user account
ANSIBLE_USER=$( grep -E '^ansible:' /etc/passwd 2>/dev/null )
if [ -n "$ANSIBLE_USER" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Dedicated 'ansible' user exists:${NC}"
    ${ECHO} "${ORAG}$ANSIBLE_USER${NC}"
    # Check if ansible user has sudo
    ANSIBLE_SUDO=$( DPRINT grep -rE '^\s*ansible\s' /etc/sudoers /etc/sudoers.d/* 2>/dev/null )
    if [ -n "$ANSIBLE_SUDO" ]; then
        ${ECHO} "${YELLOW}  Ansible sudoers entry: $ANSIBLE_SUDO${NC}"
    fi
    echo ""
fi

# Check for ansible-pull timer/cron (machine pulls its own config)
ANSIBLE_PULL_CRON=$( DPRINT grep -r 'ansible-pull\|ansible_pull' /etc/cron* /var/spool/cron* 2>/dev/null )
ANSIBLE_PULL_TIMER=$( DPRINT systemctl list-timers --all 2>/dev/null | grep -i ansible )
if [ -n "$ANSIBLE_PULL_CRON" ] || [ -n "$ANSIBLE_PULL_TIMER" ]; then
    ANSIBLE_MANAGED=true
    ${ECHO} "${BLUE}[+] Ansible-pull scheduled tasks found:${NC}"
    [ -n "$ANSIBLE_PULL_CRON" ] && ${ECHO} "${ORAG}Cron: $ANSIBLE_PULL_CRON${NC}"
    [ -n "$ANSIBLE_PULL_TIMER" ] && ${ECHO} "${ORAG}Timer: $ANSIBLE_PULL_TIMER${NC}"
    echo ""
fi

if [ "$ANSIBLE_MANAGED" = false ]; then
    ${ECHO} "${YELLOW}[-] No signs of Ansible remote management detected${NC}"
fi

APACHE2=false
NGINX=false
checkService()
{
    serviceList=$1
    serviceToCheckExists=$2
    serviceAlias=$3                

	serviceGrep="$serviceToCheckExists"
	if [ -n "$serviceAlias" ]; then
		serviceGrep="$serviceAlias\|$serviceToCheckExists"
	fi

	if echo "$serviceList" | grep -qi "$serviceGrep"; then
		${ECHO} "\n${BLUE}[+] $serviceToCheckExists is on this machine${NC}\n"

		if [ "$( DPRINT sockstat -l | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(sockstat -l | grep -i "$serviceGrep" | grep -i ":" | awk 'BEGIN {ORS=" and " } {print $6}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		elif [ "$( DPRINT netstat -an 2>/dev/null | grep 'LISTEN' | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(netstat -an | grep 'LISTEN' | awk 'BEGIN {ORS=" and "} {print $1, $4}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		elif [ "$( DPRINT netstat -tulpn | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(netstat -tulpn | grep -i "$serviceGrep" | awk 'BEGIN {ORS=" and "} {print $1, $4}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		elif [ "$( DPRINT ss -blunt -p | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(ss -blunt -p | grep -i "$serviceGrep" | awk 'BEGIN {ORS=" and " } {print $1,$5}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		fi
	fi

}

if checkService "$SERVICES"  'ssh' | grep -qi "is on this machine"; then checkService "$SERVICES" 'ssh' ; SSH=true ;fi
if checkService "$SERVICES"  'docker' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'docker'

    ACTIVECONTAINERS=$( docker ps )
    if [ -n "$ACTIVECONTAINERS" ]; then
        echo "Current Active Containers"
        ${ECHO} "${ORAG}$ACTIVECONTAINERS${NC}\n"
    fi

    ANONMOUNTS=$( docker ps -q | DPRINT xargs -n 1 docker inspect --format '{{if .Mounts}}{{.Name}}: {{range .Mounts}}{{.Source}} -> {{.Destination}}{{end}}{{end}}' | grep -vE '^$' | sed 's/^\///g' )
    if [ -n "$ANONMOUNTS" ]; then
        echo "Anonymous Container Mounts (host -> container)"
        ${ECHO} "${ORAG}$ANONMOUNTS${NC}\n"
    fi

    VOLUMES="$( DPRINT docker volume ls --format "{{.Name}}" )"
    if [ -n "$VOLUMES" ]; then
        echo "Volumes"
        for v in $VOLUMES; do
            container=$( DPRINT docker ps -a --filter volume=$v --format '{{.Names}}' | tr '\n' ',' | sed 's/,$//g' )
            if [ -n "$container" ]; then
                mountpoint=$( echo $( DPRINT docker volume inspect --format '{{.Name}}: {{.Mountpoint}}' $v ) | awk -F ': ' '{print $2}' )
                ${ECHO} "${ORAG}$v -> $mountpoint used by $container${NC}"
            fi
        done
        echo ""
    fi
fi

if checkService "$SERVICES"  'cockpit' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'cockpit'
    ${ECHO} "${ORAG}[!] WE PROBABLY SHOULD KILL COCKPIT${NC}"
fi

if checkService "$SERVICES" 'kubelet' 'kube-apiserver' | grep -qi "is on this machine" || \
   checkService "$SERVICES" 'k3s' | grep -qi "is on this machine" || \
   checkService "$SERVICES" 'k3s-server' | grep -qi "is on this machine" || \
   checkService "$SERVICES" 'k3s-agent' | grep -qi "is on this machine"; then
    
    # Display whichever service was found
    checkService "$SERVICES" 'kubelet' 'kube-apiserver' 2>/dev/null
    checkService "$SERVICES" 'k3s' 2>/dev/null
    checkService "$SERVICES" 'k3s-server' 2>/dev/null
    checkService "$SERVICES" 'k3s-agent' 2>/dev/null
    
    K8S=true

    # Check if kubectl is available
    if command -v kubectl >/dev/null 2>&1; then
        ${ECHO} "${BLUE}[+] kubectl is available${NC}\n"
        
        # Get cluster info
        CLUSTERINFO=$( DPRINT kubectl cluster-info 2>/dev/null )
        if [ -n "$CLUSTERINFO" ]; then
            echo "Cluster Information"
            ${ECHO} "${ORAG}$CLUSTERINFO${NC}\n"
        fi
        
        # Get nodes
        NODES=$( DPRINT kubectl get nodes -o wide 2>/dev/null )
        if [ -n "$NODES" ]; then
            echo "Kubernetes Nodes"
            ${ECHO} "${ORAG}$NODES${NC}\n"
        fi
        
        # Get all pods with IP addresses
        PODS=$( DPRINT kubectl get pods --all-namespaces -o wide 2>/dev/null )
        if [ -n "$PODS" ]; then
            echo "Kubernetes Pods (All Namespaces)"
            ${ECHO} "${ORAG}$PODS${NC}\n"
        fi
        
        # Get pod network CIDR if available
        PODCIDR=$( DPRINT kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' 2>/dev/null )
        if [ -n "$PODCIDR" ]; then
            echo "Pod Network CIDR(s)"
            ${ECHO} "${ORAG}$PODCIDR${NC}\n"
        fi
        
        # Get services with their ClusterIPs
        SERVICES_K8S=$( DPRINT kubectl get services --all-namespaces -o wide 2>/dev/null )
        if [ -n "$SERVICES_K8S" ]; then
            echo "Kubernetes Services"
            ${ECHO} "${ORAG}$SERVICES_K8S${NC}\n"
        fi
        
        # Check for running containers via crictl (if available)
        if command -v crictl >/dev/null 2>&1; then
            CRICTL_PODS=$( DPRINT crictl pods 2>/dev/null )
            if [ -n "$CRICTL_PODS" ]; then
                echo "Running Pods (via crictl)"
                ${ECHO} "${ORAG}$CRICTL_PODS${NC}\n"
            fi
        fi
    else
        ${ECHO} "${RED}[!] kubectl not available - cannot gather detailed Kubernetes information${NC}\n"
        
        # Try to find kubeconfig
        KUBECONFIG_LOCS=$( DPRINT find /root /home -name "*.kubeconfig" -o -name "config" -path "*/.kube/*" 2>/dev/null )
        if [ -n "$KUBECONFIG_LOCS" ]; then
            echo "Found kubeconfig files at:"
            ${ECHO} "${YELLOW}$KUBECONFIG_LOCS${NC}\n"
        fi
    fi
    
    # Check for k3s specifically
    if command -v k3s >/dev/null 2>&1; then
        ${ECHO} "${BLUE}[+] k3s detected${NC}\n"
        K3S_NODES=$( DPRINT k3s kubectl get nodes -o wide 2>/dev/null )
        if [ -n "$K3S_NODES" ]; then
            echo "k3s Nodes"
            ${ECHO} "${ORAG}$K3S_NODES${NC}\n"
        fi
    fi
    
    # Check for microk8s
    if command -v microk8s >/dev/null 2>&1; then
        ${ECHO} "${BLUE}[+] microk8s detected${NC}\n"
        MICROK8S_STATUS=$( DPRINT microk8s status 2>/dev/null )
        if [ -n "$MICROK8S_STATUS" ]; then
            echo "microk8s Status"
            ${ECHO} "${ORAG}$MICROK8S_STATUS${NC}\n"
        fi
    fi
fi

if checkService "$SERVICES" 'apache2' 'httpd' | grep -qi "is on this machine"; then
    checkService "$SERVICES" 'apache2' 'httpd'

    if [ $IS_BSD = true ]; then
        APACHE2VHOSTS=$(tail -n +1 /usr/local/etc/apache24/httpd.conf /usr/local/etc/apache24/extra/httpd-vhosts.conf |
            grep -v '#' |
            grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
    else
        if [ -d "/etc/httpd" ]; then
            APACHE2VHOSTS=$(tail -n +1 /etc/httpd/conf.d/* /etc/httpd/conf/httpd.conf |
                grep -v '#' |
                grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
        else
            APACHE2VHOSTS=$(tail -n +1 /etc/apache2/sites-enabled/* /etc/apache2/apache2.conf |
                grep -v '#' |
                grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
        fi
    fi

    ${ECHO} "\n[!] Configuration Details\n"
    ${ECHO} "${ORAG}$APACHE2VHOSTS${NC}"
    APACHE2=true
fi

if checkService "$SERVICES"  'ftp' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'ftp'
    FTPCONF=$(cat /etc/*ftp* | grep -v '#' | grep -E 'anonymous_enable|guest_enable|no_anon_password|write_enable')
    ${ECHO} "\n[!] Configuration Details\n"
    ${ECHO} "${ORAG}$FTPCONF${NC}"
fi


if checkService "$SERVICES"  'nginx' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'nginx'
    NGINXCONFIG=$(tail -n +1 /etc/nginx/sites-enabled/* /etc/nginx/nginx.conf| grep -v '#'  | grep -E '==>|server|listen|root|server_name|proxy_')
    ${ECHO} "\n[!] Configuration Details\n"
    ${ECHO} "${ORAG}$NGINXCONFIG${NC}"
    NGINX=true
fi

sql_test(){

    if [ -f /lib/systemd/system/mysql.service ]; then
        SQL_SYSD=/lib/systemd/system/mysql.service
    elif [ -f /lib/systemd/system/mariadb.service ]; then
        SQL_SYSD=/lib/systemd/system/mariadb.service
    fi
    
    if [ -n "$SQL_SYSD" ]; then
        SQL_SYSD_INFO=$( grep -RE '^(User=|Group=)' $SQL_SYSD )
    fi
    
    if [ -d /etc/mysql ]; then
        SQLDIR=/etc/mysql
    elif [ -d /etc/my.cnf.d/ ]; then
        SQLDIR=/etc/my.cnf.d/
    fi

    if [ -n "$SQLDIR" ]; then
        SQLCONFINFO=$( DPRINT find $SQLDIR *sql*.cnf *-server.cnf | sed 's/:user\s*/ ===> user /' | sed 's/bind-address\s*/ ===> bind-address /' )
    fi

    if [ -n "$SQLCONFINFO" ]; then
        ${ECHO} "${ORAG}$SQLCONFINFO${NC}"
    fi

    if [ -n "$SQL_SYSD_INFO" ]; then
        ${ECHO} "${ORAG}$SQL_SYSD:\n$SQL_SYSD_INFO${NC}\n"
    fi

    SQL_AUTH=1

    if mysql -uroot -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login as root, with root and no password${NC}\n"
        SQLCMD="mysql -uroot"
    fi

    if mysql -uroot -proot -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login with root:root${NC}\n"
        SQLCMD="mysql -uroot -proot"
    fi

    if mysql -uroot -ppassword -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login with root:password${NC}\n"
        SQLCMD="mysql -uroot -ppassword"
    fi

    if [ -n "$DEFAULT_PASS" ]; then
        if mysql -uroot -p"$DEFAULT_PASS" -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
            ${ECHO} "${RED}Can login with root:$DEFAULT_PASS${NC}\n"
            SQLCMD="mysql -uroot -p$DEFAULT_PASS"
        fi
    fi

    if [ -z "$SQLCMD" ]; then
        SQL_AUTH=0
    fi
    
    if [ "$SQL_AUTH" = 1 ]; then
        echo "SQL User Information"
        ${ECHO} "${ORAG}$( DPRINT $SQLCMD -t -e 'select user,host,plugin,authentication_string from mysql.user where password_expired="N";' )${NC}\n" 
        DATABASES=$( DPRINT $SQLCMD -t -e 'show databases' | grep -vE '^\|\s(mysql|information_schema|performance_schema|sys|test)\s+\|' )
        if [ -n "$DATABASES" ]; then
            echo "SQL Databases"
            ${ECHO} "${ORAG}$DATABASES${NC}\n"
        fi
    else
        echo "Cannot login with weak creds or default credentials"
    fi
}
if checkService "$SERVICES"  'mysql' | grep -qi "is on this machine"; then 
    MYSQL=true
    checkService "$SERVICES"  'mysql' 
    sql_test
fi

if checkService "$SERVICES"  'mariadb' | grep -qi "is on this machine"; then 
    MARIADB=true
    checkService "$SERVICES"  'mariadb'
    sql_test
fi
if checkService "$SERVICES" 'mssql-server' | grep -qi "is on this machine" ; then
    sqlserver=true
    checkService "$SERVICES" 'mssql-server' 'sqlservr'
fi
if checkService "$SERVICES"  'postgres' | grep -qi "is on this machine" ; then
    POSTGRESQL=true
    checkService "$SERVICES" 'postgres' || checkService "$SERVICES" 'postgres' 'postmaster'
    PSQLHBA=$( grep -REvh '(#|^\s*$|replication)' $( DPRINT find /etc/postgresql/ /var/lib/pgsql/ /var/lib/postgres* -name pg_hba.conf | head -n 1 ) )
    ${ECHO} "PostgreSQL Authentication Details\n"
    ${ECHO} "${ORAG}$PSQLHBA${NC}\n"

    if DPRINT psql -U postgres -c '\q'; then
        AUTH=1
        DB_CMD=" psql -U postgres -c \l "
    elif DPRINT sudo -u postgres psql -c '\q'; then
        AUTH=1
        DB_CMD=" sudo -u postgres psql -c \l "
    fi
    if [ "$AUTH" = 1 ]; then
        DATABASES="$( DPRINT $DB_CMD | grep -vE '^\s(postgres|template0|template1|\s+)\s+\|' | grep -vE '^\s*\(|^\s*$' )"
        if [ "$( echo "$DATABASES" | wc -l )" -gt 2 ]; then
            echo "PostgreSQL Databases"
            ${ECHO} "${ORAG}$DATABASES${NC}\n"
        fi
    fi
fi
if checkService "$SERVICES"  'php' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'php'
    PHP=true
    PHPINILOC=$( find / -name php.ini 2> /dev/null )
    ${ECHO} "\n[!] php.ini location(s): "
    ${ECHO} "${ORAG}$PHPINILOC${NC}"
    for ini in $PHPINILOC; do
        DISABLEDFUNCTIONS=$( grep -i 'disable_functions' $ini | grep -vE '^;|^$' )
        if [ -n "$DISABLEDFUNCTIONS" ]; then
            ${ECHO} "\n[!] Disabled Functions in $ini"
            ${ECHO} "${ORAG}$DISABLEDFUNCTIONS${NC}"
        else
            ${ECHO} "\n${RED}[!] No disabled functions found in $ini${NC}"
        fi
    done
fi

# idk about any of these
if checkService "$SERVICES"  'python' | grep -qi "is on this machine"; then checkService "$SERVICES"  'python' ; PYTHON=true; fi
if checkService "$SERVICES"  'dropbear' | grep -qi "is on this machine"; then checkService "$SERVICES"  'dropbear' ; DROPBEAR=true; fi
if checkService "$SERVICES"  'vsftpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'vsftpd' ; VSFTPD=true; fi
if checkService "$SERVICES"  'pure-ftpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'pure-ftpd' ; PUREFTPD=true; fi
if checkService "$SERVICES"  'proftpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'proftpd' ; PROFTPD=true; fi
if checkService "$SERVICES"  'xinetd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'xinetd' ; XINETD=true; fi
if checkService "$SERVICES"  'inetd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'inetd' ; INETD=true; fi
if checkService "$SERVICES"  'tftpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'tftpd' ; TFTPD=true; fi
if checkService "$SERVICES"  'atftpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'atftpd' ; ATFTPD=true; fi
if checkService "$SERVICES"  'smbd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'smbd' ; SMBD=true; fi
if checkService "$SERVICES"  'nmbd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'nmbd' ; NMBD=true; fi
if checkService "$SERVICES"  'snmpd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'snmpd' ; SNMPD=true; fi
if checkService "$SERVICES"  'ypbind' | grep -qi "is on this machine"; then checkService "$SERVICES"  'ypbind' ; YPBIND=true; fi
if checkService "$SERVICES"  'rshd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'rshd' ; RSHD=true; fi
if checkService "$SERVICES"  'rexecd' | grep -qi "is on this machine"; then checkService "$SERVICES"  'rexecd' ; REXECD=true; fi
if checkService "$SERVICES"  'rlogin' | grep -qi "is on this machine"; then checkService "$SERVICES"  'rlogin' ; RLOGIN=true; fi
if checkService "$SERVICES"  'telnet' | grep -qi "is on this machine"; then checkService "$SERVICES"  'telnet' ; TELNET=true; fi
if checkService "$SERVICES"  'squid' | grep -qi "is on this machine"; then checkService "$SERVICES"  'squid' ; SQUID=true; fi

${ECHO} "\n${GREEN}#############USER INFORMATION############${NC}\n"
${ECHO} "${BLUE}[+] Users${NC}"
${ECHO} "${YELLOW}$USERS${NC}\n"
${ECHO} "${BLUE}[+] /etc/sudoers and /etc/sudoers.d/*${NC}"
${ECHO} "${YELLOW}$SUDOERS${NC}\n"
${ECHO} "${YELLOW}$NOAUTHSUDOERS${NC}\n"
${ECHO} "${BLUE}[+] Sudo group${NC}"
${ECHO} "${YELLOW}$SUDOGROUP_LINES${NC}\n"
${ECHO} "${BLUE}[+] Funny SUIDs${NC}"
${ECHO} "${YELLOW}$SUIDS${NC}\n"
${ECHO} "${BLUE}[+] World Writeable Files${NC}"
${ECHO} "${YELLOW}$WORLDWRITEABLES${NC}\n"

${ECHO} "\n${GREEN}#############HASHES######################${NC}\n"

# Determine sha256 command
if command -v sha256sum >/dev/null 2>&1; then
    SHA256CMD='sha256sum'
elif command -v sha256 >/dev/null 2>&1; then
    # BSD sha256 outputs 'SHA256 (file) = hash', -q outputs just the hash
    SHA256CMD='sha256 -q'
else
    SHA256CMD=''
fi

MOD=$(find /lib/ /lib64/ /lib32/ /usr/lib/ /usr/lib64/ /usr/lib32/ -name "pam_unix.so" 2>/dev/null)
if [ -z "$MOD" ]; then
    ${ECHO} "${RED}[-] pam_unix.so not found${NC}"
elif [ -z "$SHA256CMD" ]; then
    ${ECHO} "${RED}[-] No sha256sum/sha256 command found${NC}"
else
    for i in $MOD; do
        i=$(echo $i | sed 's/\/pam_unix.so//g')
        ${ECHO} "${YELLOW}$i/pam_unix.so hash: ${NC}$($SHA256CMD $i/pam_unix.so | cut -d' ' -f1)""\n"
        ${ECHO} "${YELLOW}$i/pam_permit.so hash: ${NC}$($SHA256CMD $i/pam_permit.so | cut -d' ' -f1)""\n"
        ${ECHO} "${YELLOW}$i/pam_deny.so hash: ${NC}$($SHA256CMD $i/pam_deny.so | cut -d' ' -f1)""\n"
    done
fi

NOLOGIN=$(find /bin /sbin /usr -name nologin 2>/dev/null)
if [ -z "$NOLOGIN" ]; then
    ${ECHO} "${RED}[-] nologin not found${NC}"
elif [ -n "$SHA256CMD" ]; then
    for i in $NOLOGIN; do
        ${ECHO} "${YELLOW}$i hash: ${NC}$($SHA256CMD $i | cut -d' ' -f1)""\n"
    done
fi

FALSE=$(find /bin /sbin /usr -name false 2>/dev/null)
if [ -z "$FALSE" ]; then
    ${ECHO} "${RED}[-] false not found${NC}"
elif [ -n "$SHA256CMD" ]; then
    for i in $FALSE; do
        ${ECHO} "${YELLOW}$i hash: ${NC}$($SHA256CMD $i | cut -d' ' -f1)""\n"
    done
fi

TRUE=$(find /bin /sbin /usr -name true 2>/dev/null)
if [ -z "$TRUE" ]; then
    ${ECHO} "${RED}[-] true not found${NC}"
elif [ -n "$SHA256CMD" ]; then
    for i in $TRUE; do
        ${ECHO} "${YELLOW}$i hash: ${NC}$($SHA256CMD $i | cut -d' ' -f1)""\n"
    done
fi

# Process Information
${ECHO} "\n${GREEN}#############PROCESS INFORMATION############${NC}\n"
PROCESS=$( (ps -ef --forest 2>/dev/null || ps auxw 2>/dev/null || ps -ef 2>/dev/null) | tail -n 125)
${ECHO} "${YELLOW}$PROCESS${NC}\n"

# Network Information
${ECHO} "\n${GREEN}#############EXTRA NETWORK INFORMATION############${NC}\n"
${ECHO} "${BLUE}[+] Routing Table${NC}"
if [ $IS_BSD = true ]; then
    ${ECHO} "${YELLOW}$(netstat -rn 2>/dev/null)${NC}\n"
else
    ${ECHO} "${YELLOW}$(route -n 2>/dev/null)${NC}\n"
fi
${ECHO} "${BLUE}[+] ARP Table${NC}"
${ECHO} "${YELLOW}$(arp -a 2>/dev/null)${NC}\n"

# Listening Ports
${ECHO} "\n${GREEN}#############PORTS############${NC}\n"
if command -v sockstat >/dev/null ; then
    LIST_CMD="sockstat -l"
    ESTB_CMD="sockstat -46c"
elif [ $IS_OPENBSD = true ] && command -v netstat >/dev/null ; then
    LIST_CMD="netstat -an -f inet"
    ESTB_CMD="netstat -an -f inet"
elif command -v ss >/dev/null ; then
    LIST_CMD="ss -blunt -p"
    ESTB_CMD="ss -buntp"
elif command -v netstat >/dev/null ; then
    LIST_CMD="netstat -tulpn"
    ESTB_CMD="netstat -tupwn"
fi

if [ -z "$LIST_CMD" ]; then
    ${ECHO} "${RED}[-] No ss, netstat, or sockstat found. ${NC}"
else
    ${ECHO} "\n${BLUE}[+] Listening Ports${NC}"
    $LIST_CMD
    
    ${ECHO} "\n${BLUE}[+] Established Connections${NC}"
    $ESTB_CMD
fi


${ECHO} "\n${GREEN}##########################End of Output#########################${NC}"