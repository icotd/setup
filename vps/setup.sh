#!/bin/bash
set -euo pipefail

DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-alpine}"
IFACE="${IFACE:-eth0}"
TIMEZONE="${TIMEZONE:-UTC}"

cat > /root/answers.conf <<EOF
KEYMAPOPTS="us us"
HOSTNAMEOPTS="${HOSTNAME}"
INTERFACESOPTS="auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet dhcp"
DNSOPTS="-d"
TIMEZONEOPTS="-z ${TIMEZONE}"
PROXYOPTS="none"
APKREPOSOPTS="-c"
SSHDOPTS="-c openssh"
NTPOPTS="-c chrony"
DISKOPTS="-m sys ${DISK}"
EOF

setup-alpine -f /root/answers.conf
reboot
