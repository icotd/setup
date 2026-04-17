#!/bin/sh
set -eu

log() {
  echo "[bootstrap] $1"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root" >&2
    exit 1
  fi
}

detect_primary_iface() {
  IFACE="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
  if [ -z "${IFACE:-}" ]; then
    IFACE="$(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
  fi
  if [ -z "${IFACE:-}" ]; then
    echo "Could not detect network interface" >&2
    exit 1
  fi
  echo "$IFACE"
}

setup_networking_dhcp() {
  IFACE="$(detect_primary_iface)"
  log "configuring DHCP on interface: $IFACE"

  mkdir -p /etc/network

  cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet dhcp
EOF

  rc-update add networking default >/dev/null 2>&1 || true
  rc-service networking restart || true
}

disable_ipv6() {
  log "disabling IPv6"

  mkdir -p /etc/sysctl.d

  cat >/etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

  sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1 || true
}

setup_hostname() {
  log "setting hostname to alpine"

  echo "alpine" >/etc/hostname
  hostname alpine || true

  if ! grep -q '^127\.0\.0\.1[[:space:]]\+localhost' /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 localhost" >>/etc/hosts
  fi

  if ! grep -q '^127\.0\.1\.1[[:space:]]\+alpine' /etc/hosts 2>/dev/null; then
    echo "127.0.1.1 alpine" >>/etc/hosts
  fi
}

enable_community_repo() {
  log "enabling community repository"

  if [ -f /etc/apk/repositories ]; then
    awk '
      /\/community$/ {
        sub(/^#/, "")
      }
      { print }
    ' /etc/apk/repositories >/etc/apk/repositories.tmp
    mv /etc/apk/repositories.tmp /etc/apk/repositories
  fi
}

install_packages() {
  log "updating apk indexes"
  apk update

  log "installing packages"
  apk add --no-cache \
    openssh \
    caddy \
    libstdc++ \
    libgcc
}

setup_sshd() {
  log "configuring sshd"

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  if [ ! -f /root/.ssh/authorized_keys ]; then
    touch /root/.ssh/authorized_keys
  fi
  chmod 600 /root/.ssh/authorized_keys

  SSHD_CONFIG="/etc/ssh/sshd_config"

  if [ ! -f "$SSHD_CONFIG" ]; then
    touch "$SSHD_CONFIG"
  fi

  sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' \
    -e 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    -e 's/^#\?UsePAM.*/UsePAM no/' \
    "$SSHD_CONFIG"

  grep -q '^PermitRootLogin ' "$SSHD_CONFIG" || echo 'PermitRootLogin prohibit-password' >>"$SSHD_CONFIG"
  grep -q '^PubkeyAuthentication ' "$SSHD_CONFIG" || echo 'PubkeyAuthentication yes' >>"$SSHD_CONFIG"
  grep -q '^PasswordAuthentication ' "$SSHD_CONFIG" || echo 'PasswordAuthentication no' >>"$SSHD_CONFIG"
  grep -q '^KbdInteractiveAuthentication ' "$SSHD_CONFIG" || echo 'KbdInteractiveAuthentication no' >>"$SSHD_CONFIG"
  grep -q '^ChallengeResponseAuthentication ' "$SSHD_CONFIG" || echo 'ChallengeResponseAuthentication no' >>"$SSHD_CONFIG"
  grep -q '^UsePAM ' "$SSHD_CONFIG" || echo 'UsePAM no' >>"$SSHD_CONFIG"
  grep -q '^AuthorizedKeysFile ' "$SSHD_CONFIG" || echo 'AuthorizedKeysFile .ssh/authorized_keys' >>"$SSHD_CONFIG"

  ssh-keygen -A

  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd restart || rc-service sshd start
}

main() {
  require_root
  setup_networking_dhcp
  disable_ipv6
  setup_hostname
  enable_community_repo
  install_packages
  setup_sshd

  echo
  echo "bootstrap complete"
  echo
  echo "hostname: alpine"
  echo "sshd: enabled"
  echo "ssh login: SSH key only"
  echo "ipv6: disabled"
  echo "network: DHCP enabled"
  echo "packages: caddy libstdc++ libgcc openssh"
  echo
  echo "Add your public key to:"
  echo "  /root/.ssh/authorized_keys"
}

main "$@"
