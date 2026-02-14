#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

: "${GITHUB_USER:?Missing GITHUB_USER}"
: "${REPO_NAME:?Missing REPO_NAME}"
: "${DOMAIN:?Missing DOMAIN}"
: "${ADMIN_PUBKEY:?Missing ADMIN_PUBKEY}"

APP_DIR="/var/www/${REPO_NAME}"
SVC_FILE="/etc/init.d/${REPO_NAME}"
CADDYFILE="/etc/caddy/Caddyfile"

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
}

retry() {
  local n=0 max=5 delay=2
  until "$@"; do
    n=$((n+1))
    [ "$n" -ge "$max" ] && return 1
    sleep "$delay"
    delay=$((delay*2))
  done
}

install_packages() {
  retry apk update
  retry apk add --no-cache \
    bash openssh sudo curl git ca-certificates \
    caddy libstdc++ libgcc perl
}

setup_services() {
  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd start >/dev/null 2>&1 || true
  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy start >/dev/null 2>&1 || true
}

create_deploy_user() {
  id deploy >/dev/null 2>&1 || adduser -D -s /bin/ash deploy
}

setup_admin_ssh_key() {
  install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
  printf "%s\n" "$ADMIN_PUBKEY" > /home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 600 /home/deploy/.ssh/authorized_keys
}

install_bun() {
  su - deploy -c '
    if [ ! -x "$HOME/.bun/bin/bun" ]; then
      curl -fsSL https://bun.sh/install | bash
    fi
  '
  ln -sf /home/deploy/.bun/bin/bun /usr/local/bin/bun
}

generate_github_key() {
  su - deploy -c '
    set -Eeuo pipefail
    install -d -m 700 "$HOME/.ssh"

    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f "$HOME/.ssh/id_ed25519"
    fi

    # preload github host to avoid interactive prompt
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    chmod 600 "$HOME/.ssh/known_hosts"
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - deploy -c 'cat "$HOME/.ssh/id_ed25519.pub"'
  echo "======================================================="
  echo ""
  echo "Add this key to:"
  echo "Repo -> Settings -> Deploy keys -> Add deploy key"
  echo ""
  read -p "Press ENTER after adding the key..."
}

prepare_app_dir() {
  mkdir -p "$APP_DIR"
  chown -R deploy:deploy /var/www
}

clone_and_build() {
  su - deploy -c "
    set -Eeuo pipefail
    export PATH=\$HOME/.bun/bin:\$PATH

    if [ ! -d '$APP_DIR/.git' ]; then
      git clone git@github.com:${GITHUB_USER}/${REPO_NAME}.git '$APP_DIR'
    fi

    cd '$APP_DIR'
    git fetch --all --prune

    default_branch=\$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main)
    git checkout -f \"\$default_branch\" || git checkout -f main || true
    git pull --ff-only || true

    bun install --frozen-lockfile
    bun run build
  "
}

write_service() {
  cat > "$SVC_FILE" <<EOF
#!/sbin/openrc-run

name="${REPO_NAME}"
description="${REPO_NAME} (SvelteKit on Bun)"

directory="${APP_DIR}"
command="/usr/bin/env"
command_args="PORT=3000 NODE_ENV=production /usr/local/bin/bun ${APP_DIR}/build/index.js"
command_user="deploy:deploy"

pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() { need net; }

start() {
  checkpath -f -m 0644 -o deploy:deploy "\$output_log" "\$error_log"

  supervise-daemon "\${RC_SVCNAME}" \\
    --user "\${command_user}" \\
    --chdir "\${directory}" \\
    --stdout "\${output_log}" \\
    --stderr "\${error_log}" \\
    --pidfile "\${pidfile}" \\
    -- \\
    \${command} \${command_args}
}

stop() {
  supervise-daemon "\${RC_SVCNAME}" --stop --pidfile "\${pidfile}"
}
EOF

  chmod +x "$SVC_FILE"
  rc-update add "$REPO_NAME" default >/dev/null 2>&1 || true
  rc-service "$REPO_NAME" restart || true
}

write_caddyfile() {
  cat > "$CADDYFILE" <<EOF
${DOMAIN} {
  encode zstd gzip
  reverse_proxy 127.0.0.1:3000
}

www.${DOMAIN} {
  redir https://${DOMAIN}{uri} permanent
}
EOF

  caddy fmt --overwrite "$CADDYFILE" >/dev/null 2>&1 || true
  rc-service caddy reload >/dev/null 2>&1 || true
}

main() {
  need_root
  install_packages
  setup_services
  create_deploy_user
  setup_admin_ssh_key
  install_bun
  generate_github_key
  prepare_app_dir
  clone_and_build
  write_service
  write_caddyfile
}

main "$@"
