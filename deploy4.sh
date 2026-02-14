#!/bin/bash

set -euo pipefail

: "${GITHUB_USER:?Missing GITHUB_USER}"
: "${REPO_NAME:?Missing REPO_NAME}"
: "${DOMAIN:?Missing DOMAIN}"
: "${ADMIN_PUBKEY:?Missing ADMIN_PUBKEY}"

DEPLOY_USER="deploy"
APP_DIR="/var/www/${REPO_NAME}"
ENV_FILE="/etc/${REPO_NAME}.env"
SVC_FILE="/etc/init.d/${REPO_NAME}"
CADDYFILE="/etc/caddy/Caddyfile"

die() { echo "ERROR: $*" >&2; exit 1; }
as_root() { [ "$(id -u)" -eq 0 ] || die "Run as root"; }

alpine_release_minor() { cut -d. -f1,2 /etc/alpine-release; }

ensure_repos() {
  local rel; rel="$(alpine_release_minor)"

  # Prefer https
  sed -i 's|^http://|https://|g' /etc/apk/repositories || true

  # Ensure main+community exist (idempotent)
  grep -q "alpine/v${rel}/main" /etc/apk/repositories || echo "https://dl-cdn.alpinelinux.org/alpine/v${rel}/main" >> /etc/apk/repositories
  grep -q "alpine/v${rel}/community" /etc/apk/repositories || echo "https://dl-cdn.alpinelinux.org/alpine/v${rel}/community" >> /etc/apk/repositories

  # Uncomment community if present
  sed -i 's|^#\(https\?://.*/community\)$|\1|' /etc/apk/repositories || true

  apk update
}

install_pkgs() {
  apk add --no-cache \
    bash openssh sudo curl git ca-certificates nano \
    caddy \
    libstdc++ libgcc \
    perl \
    build-base python3 make g++

  update-ca-certificates || true
}

enable_services() {
  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd start >/dev/null 2>&1 || true

  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy start >/dev/null 2>&1 || true
}

create_user_and_sudo() {
  if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
    adduser -D -s /bin/ash "${DEPLOY_USER}"
  fi

  addgroup "${DEPLOY_USER}" wheel >/dev/null 2>&1 || true
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
}

install_admin_pubkey() {
  mkdir -p "/home/${DEPLOY_USER}/.ssh"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
  chmod 700 "/home/${DEPLOY_USER}/.ssh"

  printf "%s\n" "${ADMIN_PUBKEY}" > "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
}

install_bun() {
  su - "${DEPLOY_USER}" -c '
    set -euo pipefail
    if [ ! -x "$HOME/.bun/bin/bun" ]; then
      curl -fsSL https://bun.sh/install | bash
    fi
    grep -q ".bun/bin" "$HOME/.profile" 2>/dev/null || echo "export PATH=\$HOME/.bun/bin:\$PATH" >> "$HOME/.profile"
    . "$HOME/.profile"
    "$HOME/.bun/bin/bun" --version
  '
}

# Optional: make bun available to root too
symlink_bun_for_root() {
  mkdir -p /usr/local/bin
  ln -sf "/home/${DEPLOY_USER}/.bun/bin/bun" /usr/local/bin/bun
}

prime_github_known_hosts() {
  su - "${DEPLOY_USER}" -c '
    set -euo pipefail
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    chmod 644 "$HOME/.ssh/known_hosts" || true
  '
}

generate_and_print_deploy_key() {
  su - "${DEPLOY_USER}" -c '
    set -euo pipefail
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f "$HOME/.ssh/id_ed25519"
    fi
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - "${DEPLOY_USER}" -c 'cat "$HOME/.ssh/id_ed25519.pub"'
  echo "======================================================="
  echo ""
  echo "Add this key in GitHub:"
  echo "  Repo -> Settings -> Deploy keys -> Add deploy key"
  echo "  (Enable 'Allow write access' if you want this server to push.)"
  echo ""
  read -r -p "Press ENTER after you've added the deploy key... " _
}

clone_build_repo() {
  mkdir -p "${APP_DIR}"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" /var/www

  su - "${DEPLOY_USER}" -c "
    set -euo pipefail
    export PATH=\$HOME/.bun/bin:\$PATH

    if [ ! -d '${APP_DIR}/.git' ]; then
      git clone 'git@github.com:${GITHUB_USER}/${REPO_NAME}.git' '${APP_DIR}'
    fi

    cd '${APP_DIR}'
    git fetch --all --prune
    git pull --ff-only || true

    if [ -f .env.example ] && [ ! -f .env ]; then
      cp .env.example .env
    fi

    bun install --frozen-lockfile
    bun run build
    ls -la build
  "
}

write_runtime_env() {
  cat > "${ENV_FILE}" <<EOF
NODE_ENV=production
HOST=127.0.0.1
PORT=3000
EOF
  chmod 600 "${ENV_FILE}"
}

detect_entry() {
  if [ -f "${APP_DIR}/build/index.js" ]; then
    echo "${APP_DIR}/build/index.js"
    return
  fi
  if [ -f "${APP_DIR}/build/handler.js" ]; then
    echo "${APP_DIR}/build/handler.js"
    return
  fi
  die "No server entry found. Run: ls -la ${APP_DIR}/build"
}

write_openrc_service() {
  local entry; entry="$(detect_entry)"

  cat > "${SVC_FILE}" <<EOF
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

  chmod +x "${SVC_FILE}"
  rc-update add "${REPO_NAME}" default >/dev/null 2>&1 || true
  rc-service "${REPO_NAME}" restart >/dev/null 2>&1 || rc-service "${REPO_NAME}" start >/dev/null 2>&1 || true
}

write_caddy() {
  cat > "${CADDYFILE}" <<EOF
${DOMAIN} {
  reverse_proxy 127.0.0.1:3000
}

www.${DOMAIN} {
  redir https://${DOMAIN}{uri} permanent
}
EOF
  caddy fmt --overwrite "${CADDYFILE}" >/dev/null 2>&1 || true
  rc-service caddy reload >/dev/null 2>&1 || true
}

checks() {
  echo ""
  echo "== CHECKS =="
  echo "[1] bun for deploy:"
  su - "${DEPLOY_USER}" -c '/home/deploy/.bun/bin/bun -v' || true
  echo "[2] service status:"
  rc-service "${REPO_NAME}" status || true
  echo "[3] caddy status:"
  rc-service caddy status || true
  echo "[4] local app:"
  apk add --no-cache curl >/dev/null 2>&1 || true
  curl -I http://127.0.0.1:3000 || true
  echo ""
  echo "Open: https://${DOMAIN}"
  echo "If TLS fails: confirm DNS points to VPS and ports 80/443 are open."
}

main() {
  as_root
  ensure_repos
  install_pkgs
  enable_services
  create_user_and_sudo
  install_admin_pubkey
  install_bun
  symlink_bun_for_root
  prime_github_known_hosts
  generate_and_print_deploy_key
  clone_build_repo
  write_runtime_env
  write_openrc_service
  write_caddy
  checks
}

main
