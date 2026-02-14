#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

: "${GITHUB_USER:?Missing GITHUB_USER}"
: "${REPO_NAME:?Missing REPO_NAME}"
: "${DOMAIN:?Missing DOMAIN}"
: "${ADMIN_PUBKEY:?Missing ADMIN_PUBKEY (paste your Mac public key)}"

APP_DIR="/var/www/${REPO_NAME}"
ENV_FILE="/etc/${REPO_NAME}.env"
SVC_FILE="/etc/init.d/${REPO_NAME}"
CADDYFILE="/etc/caddy/Caddyfile"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
  fi
}

enable_repos() {
  # Ensure community repo is enabled (often needed for extra packages)
  if [ -f /etc/apk/repositories ]; then
    sed -i -E 's|^#(https?://.*/v[0-9]+\.[0-9]+/community)$|\1|' /etc/apk/repositories || true
  fi
}

install_packages() {
  apk update
  apk add --no-cache \
    bash \
    openssh \
    sudo \
    curl \
    git \
    ca-certificates \
    caddy \
    libstdc++ \
    libgcc \
    perl
  update-ca-certificates || true
}

setup_services() {
  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd start >/dev/null 2>&1 || true

  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy start >/dev/null 2>&1 || true
}

create_deploy_user() {
  if ! id deploy >/dev/null 2>&1; then
    adduser -D -s /bin/ash deploy
  fi

  addgroup deploy wheel >/dev/null 2>&1 || true

  mkdir -p /etc/sudoers.d
  printf "%s\n" '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
}

setup_admin_ssh_key() {
  install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
  printf "%s\n" "$ADMIN_PUBKEY" > /home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 600 /home/deploy/.ssh/authorized_keys
}

install_bun_for_deploy() {
  su - deploy -c '
    set -Eeuo pipefail
    if [ ! -x "$HOME/.bun/bin/bun" ]; then
      curl -fsSL https://bun.sh/install | bash
    fi
  '

  mkdir -p /usr/local/bin
  ln -sf /home/deploy/.bun/bin/bun /usr/local/bin/bun

  command -v bun >/dev/null 2>&1 || { echo "bun not found after install" >&2; exit 1; }
  bun --version >/dev/null 2>&1 || { echo "bun failed to run (missing libs?)" >&2; exit 1; }
}

generate_github_deploy_key() {
  su - deploy -c '
    set -Eeuo pipefail
    install -d -m 700 "$HOME/.ssh"
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f "$HOME/.ssh/id_ed25519"
    fi
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - deploy -c 'cat "$HOME/.ssh/id_ed25519.pub"'
  echo "======================================================="
  echo ""
  echo "Add this key in GitHub:"
  echo "  Repo -> Settings -> Deploy keys -> Add deploy key"
  echo "  (Enable 'Allow write access' if you want pushes from server.)"
  echo ""
  printf "Press ENTER after you've added the key... "
  read -r _ || true
}

clone_and_build() {
  mkdir -p "$APP_DIR"
  chown -R deploy:deploy /var/www

  su - deploy -c "
    set -Eeuo pipefail
    export PATH=\$HOME/.bun/bin:\$PATH

    if [ ! -d '$APP_DIR/.git' ]; then
      git clone 'git@github.com:${GITHUB_USER}/${REPO_NAME}.git' '$APP_DIR'
    fi

    cd '$APP_DIR'
    git fetch --all --prune

    default_branch=\$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
    if [ -n \"\$default_branch\" ]; then
      git checkout -f \"\$default_branch\"
    else
      git checkout -f
    fi
    git pull --ff-only

    if [ -f .env.example ] && [ ! -f .env ]; then
      cp .env.example .env
    fi

    bun install --frozen-lockfile
    bun run build
  "
}

write_env_file() {
  cat > "$ENV_FILE" <<EOF
NODE_ENV=production
HOST=127.0.0.1
PORT=3000
DATABASE_URL=${APP_DIR}/data/data.db
EOF

  # allow deploy to read (service runs bun as deploy and sources this file)
  chown root:deploy "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
}

fix_permissions() {
  mkdir -p "${APP_DIR}/data"
  touch "${APP_DIR}/data/data.db"
  chown -R deploy:deploy "${APP_DIR}/data"
  chmod 775 "${APP_DIR}/data"
  chmod 664 "${APP_DIR}/data/data.db"
}

write_openrc_service() {
  cat > "$SVC_FILE" <<EOF
#!/sbin/openrc-run

name="${REPO_NAME}"
description="${REPO_NAME} (SvelteKit on Bun)"

directory="${APP_DIR}"
command="/bin/sh"
command_user="deploy:deploy"
pidfile="/run/\${RC_SVCNAME}.pid"

output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() { need net; }

start() {
  checkpath -f -m 0644 -o deploy:deploy "\$output_log" "\$error_log"

  supervise-daemon "\$RC_SVCNAME" \\
    --user "\$command_user" \\
    --chdir "\$directory" \\
    --stdout "\$output_log" \\
    --stderr "\$error_log" \\
    --pidfile "\$pidfile" \\
    -- \\
    /bin/sh -lc 'set -a; . /etc/${REPO_NAME}.env; set +a; exec /usr/local/bin/bun build/index.js'
}

stop() {
  supervise-daemon "\$RC_SVCNAME" --stop --pidfile "\$pidfile"
}
EOF

  chmod +x "$SVC_FILE"
  rc-update add "$REPO_NAME" default >/dev/null 2>&1 || true
  rc-service "$REPO_NAME" restart
  rc-service "$REPO_NAME" status || true
}
# Optional: also ensure ENV_FILE is root-readable (service runs as root; fine at 0600 root:root)
# But the *deploy* user will read it inside the shell, so allow read:
# safest reasonable:
#   chown root:deploy /etc/$REPO_NAME.env
#   chmod 0640 /etc/$REPO_NAME.env

# Add this right after write_env_file() in your one-go script:
chmod 0640 "$ENV_FILE"
chown root:deploy "$ENV_FILE"

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
  echo "Logs:"
  echo "  tail -n 200 /var/log/${REPO_NAME}.log"
  echo "  tail -n 200 /var/log/${REPO_NAME}.err"
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
  fix_permissions
  write_openrc_service
  write_caddyfile
  final_checks
}

main "$@"
