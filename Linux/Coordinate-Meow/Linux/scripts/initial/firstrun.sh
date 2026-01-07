#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# KaliPatriot | TTU CCDC | Landon Byrge

if [ -z "$BCK" ]; then
    BCK="/root/.cache"
fi

BCK=$BCK/initial

mkdir -p $BCK

sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
setenforce 0 2>/dev/null

RHEL(){
    yum check-update -y >/dev/null

    for i in "sudo net-tools iptables iproute sed curl wget bash gcc gzip make procps socat tar auditd rsyslog tcpdump unhide strace"; do
        yum install -y $i
    done
}

SUSE(){

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar auditd rsyslog"; do
        zypper -n install -y $i
    done
}

DEBIAN(){
    apt-get -qq update >/dev/null

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar auditd rsyslog tcpdump unhide strace debsums"; do
        apt-get -qq install $i -y
    done
}

UBUNTU(){
    DEBIAN
}

ALPINE(){
    echo "http://mirrors.ocf.berkeley.edu/alpine/v3.16/community" >> /etc/apk/repositories
    apk update >/dev/null
    for i in "sudo iproute2 net-tools curl wget bash iptables util-linux-misc gcc gzip make procps socat tar tcpdump audit rsyslog"; do
        apk add $i
    done
}

SLACK(){
    slapt-get --update


    for i in "net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar tcpdump auditd rsyslog"; do
        slapt-get --install $i
    done
}

ARCH(){
    pacman -Syu --noconfirm >/dev/null

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar tcpdump auditd rsyslog"; do
        pacman -S --noconfirm $i
    done
}

BSD(){
    pkg update -f >/dev/null
    for i in "sudo bash net-tools iproute2 sed curl wget bash gcc gzip make procps socat tar tcpdump auditd rsyslog firewall"; do
        pkg install -y $i || pkg install $i
    done
}

if command -v yum >/dev/null ; then
  RHEL
elif command -v zypper >/dev/null ; then
  SUSE
elif command -v apt-get >/dev/null ; then
  if $( cat /etc/os-release | grep -qi Ubuntu ); then
      UBUNTU
  else
      DEBIAN
  fi
elif command -v apk >/dev/null ; then
  ALPINE
elif command -v slapt-get >/dev/null || ( cat /etc/os-release | grep -i slackware ) ; then
  SLACK
elif command -v pacman >/dev/null ; then
  ARCH
elif command -v pkg >/dev/null || command -v pkg_info >/dev/null; then
    BSD
fi

# backup /etc/passwd
mkdir $BCK
cp /etc/passwd $BCK/users
cp /etc/group $BCK/groups

# check our ports
if command -v sockstat >/dev/null ; then
    LIST_CMD="sockstat -l"
    ESTB_CMD="sockstat -46c"
elif command -v netstat >/dev/null ; then
    LIST_CMD="netstat -tulpn"
    ESTB_CMD="netstat -tupwn"
elif command -v ss >/dev/null ; then
    LIST_CMD="ss -blunt -p"
    ESTB_CMD="ss -buntp"
else 
    echo "No netstat, sockstat or ss found"
    LIST_CMD="echo 'No netstat, sockstat or ss found'"
    ESTB_CMD="echo 'No netstat, sockstat or ss found'"
fi

$LIST_CMD > $BCK/listen
$ESTB_CMD > $BCK/estab

# pam
mkdir -p $BCK/pam/conf
mkdir -p $BCK/pam/pam_libraries
cp -R /etc/pam.d/ $BCK/pam/conf/
MOD=$(find /lib/ /lib64/ /lib32/ /usr/lib/ /usr/lib64/ /usr/lib32/ -name "pam_unix.so" 2>/dev/null)
for m in $MOD; do
    moddir=$(dirname $m)
    mkdir -p $BCK/pam/pam_libraries/$moddir
    cp $moddir/pam*.so $BCK/pam/pam_libraries/$moddir
done

