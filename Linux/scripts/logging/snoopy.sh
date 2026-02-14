#!/bin/sh
# KaliPatriot | TTU CCDC | Landon Byrge
if [ -z "$BCK" ]; then
    BCK="/root/.cache"
fi

BCK=$BCK/initial

# Thanks ippsec
wget -O install-snoopy.sh https://github.com/a2o/snoopy/raw/install/install/install-snoopy.sh && chmod 755 install-snoopy.sh && sudo ./install-snoopy.sh stable

# change /etc/snoopy.ini to point to $BCK/snoopy.log
echo "[snoopy]" > /etc/snoopy.ini
echo "output = file:$BCK/snoopy.log" >> /etc/snoopy.ini
touch $BCK/snoopy.log
chmod 666 $BCK/snoopy.log