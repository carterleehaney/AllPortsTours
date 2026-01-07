#!/bin/sh
# TTU CCDC | Joey Milton

if [ -z "$WAZUH_MANAGER" ]; then
  echo "ERROR: You must set WAZUH_MANAGER."
  exit 1
fi

if [ -z "$WAZUH_REGISTRATION_PASSWORD" ]; then
  WAZUH_REGISTRATION_PASSWORD=""
fi

if [ -z "/etc/snoopy.ini" ]; then
  echo "ERROR: Snoopy must be installed before installing the Wazuh agent."
  exit 1
fi

ARCH=$(uname -m)


ipt=$(command -v iptables || command -v /sbin/iptables || command -v /usr/sbin/iptables)
sys=$(command -v systemctl || command -v service || command -v rc-service)

# If wazuh-manager service is running, exit
if $sys status wazuh-manager >/dev/null 2>&1 || $sys wazuh-manager status >/dev/null 2>&1; then
  echo "ERROR: Wazuh manager is running. You cannot install the agent on the same host."
  exit 1
fi

DPKG() {
  if [ $ARCH = x86_64 ]; then
    ARCH_PKG="amd64"
  elif [ $ARCH = i386 ] || [ ARCH = i686 ]; then
    ARCH_PKG="i386"
  else
    echo "ERROR: Unsupported architecture."
    exit 1
  fi

  DOWNLOAD_URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent"
  package="wazuh-agent_4.14.1-1_${ARCH_PKG}.deb"

  ( wget --no-check-certificate -O $package $DOWNLOAD_URL/$package || \
    curl -k -o $package $DOWNLOAD_URL/$package || \
    fetch --no-verify-peer -o $package $DOWNLOAD_URL/$package )

  if ( test -f $package ); then
    InstallCommand="WAZUH_MANAGER=$WAZUH_MANAGER dpkg -i $package"
    if [ -n $WAZUH_REGISTRATION_PASSWORD ]; then
      InstallCommand="WAZUH_REGISTRATION_PASSWORD=$WAZUH_REGISTRATION_PASSWORD $InstallCommand"
    fi
    eval "$InstallCommand"
  else
    echo "ERROR: Failed to download the package."
    exit 1
  fi

  add-apt-repository ppa:oisf/suricata-stable -y 2>/dev/null
  apt-get update -y 2>/dev/null
  apt-get install -y suricata auditd 2>/dev/null

}

RPM() {
  if [ $ARCH = x86_64 ]; then
    ARCH_PKG="x86_64"
  elif [ $ARCH = i386 ] || [ $ARCH = i686 ]; then
    ARCH_PKG="i386"
  else
    echo "ERROR: Unsupported architecture."
    exit 1
  fi

  DOWNLOAD_URL="https://packages.wazuh.com/4.x/yum"
  package="wazuh-agent-4.14.1-1.${ARCH_PKG}.rpm"

  ( wget -O $package $DOWNLOAD_URL/$package || \
    curl -o $package $DOWNLOAD_URL/$package || \
    fetch -o $package $DOWNLOAD_URL/$package )

  if ( test -f $package ); then
    InstallCommand="WAZUH_MANAGER=$WAZUH_MANAGER rpm -vi $package"
    if [ -n $WAZUH_REGISTRATION_PASSWORD ]; then
      InstallCommand="WAZUH_REGISTRATION_PASSWORD=$WAZUH_REGISTRATION_PASSWORD $InstallCommand"
    fi
	 eval "$InstallCommand"
  else
    echo "ERROR: Failed to download the package."
    exit 1
  fi

  yum install epel-release yum-plugin-copr -y 2>/dev/null 
  yum copr enable @oisf/suricata-8.0 -y 2>/dev/null 
  yum update -y 2>/dev/null
  yum install suricata auditd -y

}

enable_and_start() {
  $sys daemon-reload 2>/dev/null
  $sys enable wazuh-agent 2>/dev/null || $sys wazuh-agent enable 2>/dev/null
  $sys start wazuh-agent 2>/dev/null || $sys wazuh-agent start 2>/dev/null
}

is_agent_running() {
  # check if wazuh-agent service is up, if so, print 3 lines of equals, then Wazuh Agent is running, three more lines of equals and exit
  if $sys status wazuh-agent 2>/dev/null || $sys wazuh-agent status 2>/dev/null; then
    echo "==================================================================="
    echo "==================================================================="
    echo "==================================================================="
    echo "Wazuh Agent is running"
  else
    echo "==================================================================="
    echo "==================================================================="
    echo "==================================================================="
    echo "Wazuh Agent is NOT running"
  fi
  echo "==================================================================="
  echo "==================================================================="
  echo "==================================================================="
}

suricata() {
  # Download and extract rules
  cd /tmp/ && curl -LO https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || wget https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null || fetch https://rules.emergingthreats.net/open/suricata-6.0.8/emerging.rules.tar.gz 2>/dev/null
  tar -xvzf emerging.rules.tar.gz 2>/dev/null && sudo mkdir /etc/suricata/rules 2>/dev/null  && sudo mv rules/*.rules /etc/suricata/rules/ 2>/dev/null 
  chmod 777 /etc/suricata/rules/*.rules 2>/dev/null

  CONF="/etc/suricata/suricata.yaml"

  IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')

  if [ -z "$IFACE" ]; then
    IFACE="eth0"
  fi

  IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2; exit}')
  HOST_IP=${IP%%/*}

  echo "[*] Detected interface: $IFACE with IP: $HOST_IP"

  # Update HOME_NET
  sed -i -e "s|^ *HOME_NET:.*|    HOME_NET: \"${HOST_IP}\"|" "$CONF"

  # Update EXTERNAL_NET
  sed -i -e "s|^ *EXTERNAL_NET:.*|    EXTERNAL_NET: \"any\"|" "$CONF"

  # Update default-rule-path
  sed -i -e "s|^ *default-rule-path:.*|default-rule-path: /etc/suricata/rules|" "$CONF"

  # Update rule-files
  if grep -q "^ *rule-files:" "$CONF"; then
    # If rule-files exists, check if "*.rules" is already there
    if ! grep -A 5 "^ *rule-files:" "$CONF" | grep -q "\"*.rules\""; then
      # Add "*.rules" after rule-files: line
      sed -i -e "/^ *rule-files:/a\\
  - \"*.rules\"" "$CONF"
    fi
  else
    # Add rule-files after default-rule-path
    sed -i -e "/^ *default-rule-path:/a\\
rule-files:\\
  - \"*.rules\"" "$CONF"
  fi

  # Enable stats
  if grep -q "^ *stats:" "$CONF"; then
    # Update enabled in stats section
    sed -i -e "/^ *stats:/,/^[a-z]/ {
      /^ *enabled:/ s|^ *enabled:.*|  enabled: yes|
    }" "$CONF"
  else
    # Add stats section if it doesn't exist
    sed -i -e "/^# Global stats configuration/a\\
stats:\\
  enabled: yes" "$CONF"
  fi

  # Update af-packet interface - only modify lines with 2-space indent in af-packet section
  sed -i -e "/^af-packet:/,/^[a-z]/ {
    /^  - interface:/ s|^  - interface:.*|  - interface: ${IFACE}|
  }" "$CONF"

  echo "[+] Updated Suricata configuration:"
  echo "    HOME_NET: \"${HOST_IP}\""
  echo "    EXTERNAL_NET: \"any\""
  echo "    default-rule-path: /etc/suricata/rules"
  echo "    rule-files: \"*.rules\""
  echo "    stats enabled: yes"
  echo "    af-packet interface: ${IFACE}"
}

suricata_running() {
    $sys restart suricata 2>/dev/null || $sys suricata restart 2>/dev/null
  
  if $sys status suricata >/dev/null 2>&1 || $sys suricata status >/dev/null 2>&1; then
    echo "==================================================================="
    echo "==================================================================="
    echo "==================================================================="
    echo "Suricata is running"
  else
    echo "==================================================================="
    echo "==================================================================="
    echo "==================================================================="
    echo "Suricata is NOT running"
  fi
  echo "==================================================================="
  echo "==================================================================="
  echo "==================================================================="
}


if command -v dpkg >/dev/null ; then
  DPKG
elif command -v rpm >/dev/null ; then
  RPM
else
  echo "ERROR: Unsupported package manager."
  exit 1
fi


suricata
enable_and_start
is_agent_running
suricata_running