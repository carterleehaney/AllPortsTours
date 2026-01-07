#!/bin/sh
# TTU CCDC | Joey Milton

sys=$(command -v systemctl || command -v service || command -v rc-service)

add-apt-repository ppa:oisf/suricata-stable -y 2>/dev/null
apt-get update -y 2>/dev/null
apt-get install -y suricata 

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

suricata_running