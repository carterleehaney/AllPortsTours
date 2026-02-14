#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# KaliPatriot | TTU CCDC | Landon Byrge
# Foister is just happy to be here

if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 2>/dev/null
fi

RHEL(){
    yum check-update -y >/dev/null
    yum install -y epel-release 2>/dev/null

    for i in "sudo net-tools iptables iproute sed curl wget bash gcc gzip make procps socat tar audit rsyslog tcpdump strace bpftrace traceroute binutils lsof bind-utils e2fsprogs diffutils unzip ca-certificates"; do
        yum install -y $i
    done
}

SUSE(){

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar auditd rsyslog tcpdump unhide strace bpftrace traceroute binutils lsof bind-utils e2fsprogs diffutils unzip ca-certificates"; do
        zypper -n install -y $i
    done
}

DEBIAN(){
    apt-get -qq update >/dev/null

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar auditd rsyslog tcpdump unhide strace debsums bpftrace traceroute binutils lsof dnsutils e2fsprogs diffutils unzip ca-certificates python3"; do
        apt-get -qq install $i -y
    done
}

UBUNTU(){
    DEBIAN
}

ALPINE(){
    echo "http://mirrors.ocf.berkeley.edu/alpine/v3.16/community" >> /etc/apk/repositories
    apk update >/dev/null
    for i in "sudo iproute2 net-tools curl wget bash iptables util-linux-misc gcc gzip make procps socat tar tcpdump audit rsyslog strace bpftrace traceroute binutils lsof bind-tools e2fsprogs diffutils unzip ca-certificates python3"; do
        apk add $i
    done
}

SLACK(){
    slapt-get --update


    for i in "net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar tcpdump strace auditd rsyslog bpftrace traceroute binutils lsof bind-utils e2fsprogs diffutils unzip ca-certificates python3"; do
        slapt-get --install $i
    done
}

ARCH(){
    pacman -Syu --noconfirm >/dev/null

    for i in "sudo net-tools iptables iproute2 sed curl wget bash gcc gzip make procps socat tar tcpdump strace auditd rsyslog bpftrace traceroute binutils lsof bind-tools e2fsprogs diffutils unzip ca-certificates python"; do
        pacman -S --noconfirm $i
    done
}

FREEBSD(){
    pkg update -f >/dev/null
    for i in "sudo bash curl wget gcc gmake socat tcpdump rsyslog binutils lsof bind-tools ca_root_nss python3 ipmitool"; do
        pkg install -y $i
    done
}

OPENBSD(){
    for i in "bash curl wget gcc gmake socat rsyslog lsof python3"; do
        pkg_add $i 2>/dev/null
    done
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
elif command -v pkg_add >/dev/null && uname -s | grep -qi openbsd; then
  OPENBSD
elif command -v pkg >/dev/null; then
  FREEBSD
fi

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



