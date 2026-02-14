#!/usr/bin/env sh
# Alpine all-in-one: Bun + private GitHub repo + OpenRC service + Caddy (Let's Encrypt)
# Usage (as root):
#   DOMAIN='brighton.ethsaas.cloud' GITHUB_USER='icotd' REPO_NAME='brighton-pms' ADMIN_PUBKEY='ssh-ed25519 AAAA... you@mac' sh setup.sh
#
# Notes:
# - This script assumes Alpine is already installed and booted (it does NOT run the interactive `setup-alpine`).
# - Your DNS must point DOMAIN -> VPS IP and ports 80/443 must be reachable for Let's Encrypt.
# - For private GitHub repo: it generates a deploy key, prints it, and pauses so you can add it as a Deploy Key in GitHub.

set -eu

: "${GITHUB_USER:?Missing GITHUB_USER}"
: "${REPO_NAME:?Missing REPO_NAME}"
: "${DOMAIN:?Missing DOMAIN}"
: "${ADMIN_PUBKEY:?Missing ADMIN_PUBKEY (paste your public key)}"

APP_DIR="/var/www/${REPO_NAME}"
ENV_FILE="/etc/${REPO_NAME}.env"
SVC_FILE="/etc/init.d/${REPO_NAME}"
CADDYFILE="/etc/caddy/Caddyfile"

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
}

enable_repos() {
  # Ensure community is enabled (needed for sudo, etc.)
  if grep -qE '^[#]*https?://.*/v[0-9]+\.[0-9]+/community' /etc/apk/repositories; then
    sed -i 's|^#\(https\?://.*/community\)$|\1|' /etc/apk/repositories
  fi
}

install_packages() {
  apk update
  apk add --no-cache \
    bash openssh sudo curl git ca-certificates nano \
    caddy \
    libstdc++ libgcc \
    perl \
    build-base python3 make g++
  update-ca-certificates || true
}

setup_services() {
  rc-update add sshd default || true
  rc-service sshd start || true

  rc-update add caddy default || true
  rc-service caddy start || true
}

create_deploy_user() {
  if ! id deploy >/dev/null 2>&1; then
    adduser -D -s /bin/ash deploy
  fi

  addgroup deploy wheel 2>/dev/null || true
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
}

setup_admin_ssh_key() {
  mkdir -p /home/deploy/.ssh
  chown -R deploy:deploy /home/deploy/.ssh
  chmod 700 /home/deploy/.ssh

  # Install ADMIN pubkey as authorized_keys
  printf "%s\n" "$ADMIN_PUBKEY" > /home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 600 /home/deploy/.ssh/authorized_keys
}

install_bun_for_deploy() {
  su - deploy -c '
    set -eu
    command -v bun >/dev/null 2>&1 && exit 0
    curl -fsSL https://bun.sh/install | bash
    grep -q ".bun/bin" ~/.profile 2>/dev/null || echo "export PATH=\$HOME/.bun/bin:\$PATH" >> ~/.profile
  '
}

generate_github_deploy_key() {
  su - deploy -c '
    set -eu
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [ ! -f ~/.ssh/id_ed25519 ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f ~/.ssh/id_ed25519
    fi
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - deploy -c 'cat ~/.ssh/id_ed25519.pub'
  echo "======================================================="
  echo ""
  echo "Add this key in GitHub:"
  echo "  Repo -> Settings -> Deploy keys -> Add deploy key"
  echo "  (Enable 'Allow write access' if you want pushes from server.)"
  echo ""
  printf "Press ENTER after you've added the key... "
  read _ || true
}

clone_and_build() {
  mkdir -p "$APP_DIR"
  chown -R deploy:deploy /var/www

  su - deploy -c "
    set -eu
    export PATH=\$HOME/.bun/bin:\$PATH
    mkdir -p '$APP_DIR'
    if [ ! -d '$APP_DIR/.git' ]; then
      git clone 'git@github.com:${GITHUB_USER}/${REPO_NAME}.git' '$APP_DIR'
    fi
    cd '$APP_DIR'
    git fetch --all --prune
    git checkout -f
    git pull --ff-only

    if [ -f .env.example ] && [ ! -f .env ]; then
      cp .env.example .env
    fi

    bun install --frozen-lockfile
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
  cat > "$SVC_FILE" <<EOF
#!/sbin/openrc-run

name="${REPO_NAME}"
description="SvelteKit on Bun (${REPO_NAME})"
command="/home/deploy/.bun/bin/bun"
command_args="${APP_DIR}/build/index.js"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() { need net; }

start_pre() {
  checkpath --file --owner deploy:deploy --mode 0644 "\$output_log" "\$error_log"
  if [ -f "${ENV_FILE}" ]; then
    set -a
    . "${ENV_FILE}"
    set +a
  fi
}
EOF
  chmod +x "$SVC_FILE"
  rc-update add "$REPO_NAME" default || true
  rc-service "$REPO_NAME" restart || rc-service "$REPO_NAME" start
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
  rc-service caddy reload || true
}

final_checks() {
  echo ""
  echo "=== STATUS ==="
  rc-service "$REPO_NAME" status || true
  rc-service caddy status || true
  echo ""
  echo "Try local proxy test:"
  echo "  curl -I http://127.0.0.1:3000"
  echo ""
  echo "Then open:"
  echo "  https://${DOMAIN}"
  echo ""
  echo "If TLS doesn't issue, confirm:"
  echo "  - DNS A/AAAA for ${DOMAIN} points to this VPS"
  echo "  - Ports 80 and 443 are reachable inbound"
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
  generate_github_deploy_key
  clone_and_build
  write_env_file
  write_openrc_service
  write_caddyfile
  final_checks
}

main "$@"
