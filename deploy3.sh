#!/bin/bash
# Alpine all-in-one: Bun + private GitHub repo + OpenRC service + Caddy (Let's Encrypt)
#
# Run as root AFTER Alpine is installed & booted (not from ISO).
#
# Usage:
#   export GITHUB_USER='icotd'
#   export REPO_NAME='brighton-pms'
#   export DOMAIN='brighton.ethsaas.cloud'
#   export ADMIN_PUBKEY='ssh-ed25519 AAAA... your-mac-key ...'
#   ./setup.sh
#
# What it does:
# - Fixes apk repos (adds main+community for current Alpine release, prefers https)
# - Installs packages (caddy, openssh, sudo, bun deps, perl, build tools)
# - Creates deploy user + installs your ADMIN_PUBKEY for SSH login
# - Installs Bun for deploy user and verifies it
# - Generates GitHub deploy key (prints it) and pauses for you to add it to GitHub repo Deploy Keys
# - Clones your private repo via SSH into /var/www/$REPO_NAME
# - Copies .env.example -> .env (if present and .env missing)
# - Builds (bun install + bun run build)
# - Creates OpenRC service to run build/index.js
# - Configures Caddy for DOMAIN + www redirect
#
# Requirements:
# - DNS A/AAAA for DOMAIN points to this VPS
# - Ports 80/443 reachable inbound for Let's Encrypt
#
set -euo pipefail

: "${GITHUB_USER:?Missing GITHUB_USER}"
: "${REPO_NAME:?Missing REPO_NAME}"
: "${DOMAIN:?Missing DOMAIN}"
: "${ADMIN_PUBKEY:?Missing ADMIN_PUBKEY (paste your public key)}"

DEPLOY_USER="deploy"
APP_DIR="/var/www/${REPO_NAME}"
ENV_FILE="/etc/${REPO_NAME}.env"
SVC_FILE="/etc/init.d/${REPO_NAME}"
CADDYFILE="/etc/caddy/Caddyfile"

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
}

enable_repos() {
  local rel
  rel="$(cut -d. -f1,2 /etc/alpine-release)"

  # Prefer https in existing lines
  sed -i 's|^http://|https://|g' /etc/apk/repositories || true

  # Ensure main+community exist for this release
  grep -q "alpine/v${rel}/main" /etc/apk/repositories || echo "https://dl-cdn.alpinelinux.org/alpine/v${rel}/main" >> /etc/apk/repositories
  grep -q "alpine/v${rel}/community" /etc/apk/repositories || echo "https://dl-cdn.alpinelinux.org/alpine/v${rel}/community" >> /etc/apk/repositories

  # Uncomment community if present
  sed -i 's|^#\(https\?://.*/community\)$|\1|' /etc/apk/repositories || true

  apk update
}

install_packages() {
  apk add --no-cache \
    bash openssh sudo curl git ca-certificates nano \
    caddy \
    libstdc++ libgcc \
    perl \
    build-base python3 make g++

  update-ca-certificates || true
}

setup_services() {
  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd start >/dev/null 2>&1 || true

  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy start >/dev/null 2>&1 || true
}

create_deploy_user() {
  if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
    adduser -D -s /bin/ash "$DEPLOY_USER"
  fi

  addgroup "$DEPLOY_USER" wheel >/dev/null 2>&1 || true
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
}

setup_admin_ssh_key() {
  mkdir -p "/home/${DEPLOY_USER}/.ssh"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
  chmod 700 "/home/${DEPLOY_USER}/.ssh"

  printf "%s\n" "$ADMIN_PUBKEY" > "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
}

install_bun_for_deploy() {
  su - "$DEPLOY_USER" -c '
    set -euo pipefail
    if [ ! -x "$HOME/.bun/bin/bun" ]; then
      curl -fsSL https://bun.sh/install | bash
    fi
    grep -q ".bun/bin" "$HOME/.profile" 2>/dev/null || echo "export PATH=\$HOME/.bun/bin:\$PATH" >> "$HOME/.profile"
    . "$HOME/.profile"
    "$HOME/.bun/bin/bun" --version
  '
}

generate_github_deploy_key() {
  su - "$DEPLOY_USER" -c '
    set -euo pipefail
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f "$HOME/.ssh/id_ed25519"
    fi
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - "$DEPLOY_USER" -c 'cat "$HOME/.ssh/id_ed25519.pub"'
  echo "======================================================="
  echo ""
  echo "Add this key in GitHub:"
  echo "  Repo -> Settings -> Deploy keys -> Add deploy key"
  echo "  (Enable 'Allow write access' if you want pushes from server.)"
  echo ""
  read -r -p "Press ENTER after you've added the key... " _
}

prime_known_hosts() {
  # Avoid interactive prompt on first git clone
  su - "$DEPLOY_USER" -c '
    set -euo pipefail
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    chmod 644 "$HOME/.ssh/known_hosts" || true
  '
}

clone_and_build() {
  mkdir -p "$APP_DIR"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" /var/www

  su - "$DEPLOY_USER" -c "
    set -euo pipefail
    export PATH=\$HOME/.bun/bin:\$PATH

    if [ ! -d '$APP_DIR/.git' ]; then
      git clone 'git@github.com:${GITHUB_USER}/${REPO_NAME}.git' '$APP_DIR'
    fi

    cd '$APP_DIR'
    git fetch --all --prune
    git pull --ff-only || true

    if [ -f .env.example ] && [ ! -f .env ]; then
      cp .env.example .env
    fi

    bun install --frozen-lockfile

    # If the repo has a perl-based postbuild, perl is installed already.
    bun run build

    ls -la build || true
  "
}

write_env_file() {
  cat > "$ENV_FILE" <<EOF
NODE_ENV=production
HOST=127.0.0.1
PORT=3000
EOF
  chmod 600 "$ENV_FILE"
}

write_openrc_service() {
  # Detect server entry
  local entry="${APP_DIR}/build/index.js"
  if [ ! -f "$entry" ] && [ -f "${APP_DIR}/build/handler.js" ]; then
    # fallback for some outputs
    entry="${APP_DIR}/build/handler.js"
  fi

  if [ ! -f "$entry" ]; then
    echo "ERROR: Could not find app entry in ${APP_DIR}/build"
    echo "Run: ls -la ${APP_DIR}/build"
    exit 1
  fi

  cat > "$SVC_FILE" <<EOF
#!/sbin/openrc-run

name="${REPO_NAME}"
description="SvelteKit on Bun (${REPO_NAME})"
command="/home/${DEPLOY_USER}/.bun/bin/bun"
command_args="${entry}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() { need net; }

start_pre() {
  checkpath --file --owner ${DEPLOY_USER}:${DEPLOY_USER} --mode 0644 "\$output_log" "\$error_log"
  if [ -f "${ENV_FILE}" ]; then
    set -a
    . "${ENV_FILE}"
    set +a
  fi
}
EOF

  chmod +x "$SVC_FILE"
  rc-update add "$REPO_NAME" default >/dev/null 2>&1 || true
  rc-service "$REPO_NAME" restart >/dev/null 2>&1 || rc-service "$REPO_NAME" start >/dev/null 2>&1 || true
}

write_caddyfile() {
  cat > "$CADDYFILE" <<EOF
${DOMAIN} {
  reverse_proxy 127.0.0.1:3000
}

www.${DOMAIN} {
  redir https://${DOMAIN}{uri} permanent
}
EOF

  caddy fmt --overwrite "$CADDYFILE" >/dev/null 2>&1 || true
  rc-service caddy reload >/dev/null 2>&1 || true
}

final_checks() {
  echo ""
  echo "=== STATUS ==="
  rc-service "$REPO_NAME" status || true
  rc-service caddy status || true
  echo ""
  echo "Local app test (should be 200/3xx):"
  echo "  curl -I http://127.0.0.1:3000"
  echo ""
  echo "Open:"
  echo "  https://${DOMAIN}"
  echo ""
  echo "If TLS doesn't issue, confirm:"
  echo "  - DNS A/AAAA for ${DOMAIN} points to this VPS"
  echo "  - Ports 80 and 443 are reachable inbound"
  echo ""
  echo "Bun location (deploy user):"
  echo "  /home/${DEPLOY_USER}/.bun/bin/bun -v"
  echo ""
}

main() {
  need_root
  enable_repos
  install_packages
  setup_services
  create_deploy_user
  setup_admin_ssh_key
  install_bun_for_deploy
  prime_known_hosts
  generate_github_deploy_key
  clone_and_build
  write_env_file
  write_openrc_service
  write_caddyfile
  final_checks
}

main "$@"
