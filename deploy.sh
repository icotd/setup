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
APK_REPOS="/etc/apk/repositories"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }; }

retry() {
  local n=0 max=5 delay=2
  until "$@"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      echo "FAILED: $*" >&2
      return 1
    fi
    sleep "$delay"
    delay=$((delay*2))
  done
}

alpine_branch() {
  local v
  v="$(cut -d. -f1-2 </etc/alpine-release 2>/dev/null || echo "3.22")"
  printf "v%s\n" "$v"
}

ensure_repos() {
  local branch mirror
  branch="$(alpine_branch)"
  mirror="$(grep -E '^(#\s*)?https?://.*/alpine/' -m1 "$APK_REPOS" 2>/dev/null \
    | sed -E 's/^#\s*//; s|(https?://.*/alpine)/.*|\1|' || true)"
  [ -n "$mirror" ] || mirror="https://dl-cdn.alpinelinux.org/alpine"

  mkdir -p "$(dirname "$APK_REPOS")"
  touch "$APK_REPOS"

  if ! grep -Eq '/(main|community)$' "$APK_REPOS"; then
    cat >"$APK_REPOS" <<EOF
${mirror}/${branch}/main
${mirror}/${branch}/community
EOF
  else
    sed -i -E 's|^#\s*(https?://.*/alpine/[^/]+/main)$|\1|g' "$APK_REPOS" || true
    sed -i -E 's|^#\s*(https?://.*/alpine/[^/]+/community)$|\1|g' "$APK_REPOS" || true
    grep -Eq "^${mirror}/${branch}/main$" "$APK_REPOS"      || echo "${mirror}/${branch}/main" >>"$APK_REPOS"
    grep -Eq "^${mirror}/${branch}/community$" "$APK_REPOS" || echo "${mirror}/${branch}/community" >>"$APK_REPOS"
  fi
}

install_packages() {
  ensure_repos
  retry apk update

  retry apk add --no-cache \
    bash openssh curl git ca-certificates \
    libstdc++ libgcc perl

  retry apk add --no-cache libcap
  apk add --no-cache sudo >/dev/null 2>&1 || true
  retry apk add --no-cache caddy caddy-openrc

  update-ca-certificates >/dev/null 2>&1 || true
}

setup_services() {
  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd restart >/dev/null 2>&1 || true

  rc-update add caddy default >/dev/null 2>&1 || true
  rc-service caddy restart >/dev/null 2>&1 || true
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
    set -Eeuo pipefail
    if [ ! -x "$HOME/.bun/bin/bun" ]; then
      curl -fsSL https://bun.sh/install | bash
    fi
    "$HOME/.bun/bin/bun" --version >/dev/null
  '
}

generate_github_key() {
  su - deploy -c '
    set -Eeuo pipefail
    install -d -m 700 "$HOME/.ssh"

    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -C "vps-deploy" -N "" -f "$HOME/.ssh/id_ed25519"
    fi

    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    chmod 600 "$HOME/.ssh/known_hosts"
  '

  echo ""
  echo "================== GITHUB DEPLOY KEY =================="
  su - deploy -c 'cat "$HOME/.ssh/id_ed25519.pub"'
  echo "======================================================="
  echo ""
  echo "Add this key to: Repo -> Settings -> Deploy keys -> Add deploy key"
  echo ""
  printf "Press ENTER after adding the key..."
  read -r _ < /dev/tty
}

prepare_app_dir() {
  mkdir -p /var/www "$APP_DIR"
  chown -R deploy:deploy /var/www
}

clone_and_build() {
  su - deploy -c "
    set -Eeuo pipefail
    export PATH=\$HOME/.bun/bin:\$PATH

    if [ ! -d '$APP_DIR/.git' ]; then
      git clone 'git@github.com:${GITHUB_USER}/${REPO_NAME}.git' '$APP_DIR'
    fi

    cd '$APP_DIR'
    git fetch --all --prune

    default_branch=\$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main)
    git checkout -f \"\$default_branch\" || git checkout -f main
    git pull --ff-only

    bun install --frozen-lockfile
    bun run build

    # patch build/handler.js only if needed
    if [ -f build/handler.js ]; then
      if grep -q 'server\\.websocket()' build/handler.js; then
        perl -i -pe 's/const websocket = server\\.websocket\\(\\);/const websocket = server.websocket?.();/g' build/handler.js
      fi
    fi
  "

  chown -R deploy:deploy "$APP_DIR"

  # do NOT create data; only fix perms if it exists
  if [ -d "$APP_DIR/data" ]; then
    chown -R deploy:deploy "$APP_DIR/data"
  fi
}

write_app_service() {
  cat > "$SVC_FILE" <<EOF
#!/sbin/openrc-run

name="${REPO_NAME}"
description="${REPO_NAME} (SvelteKit on Bun)"

directory="${APP_DIR}"
command="/home/deploy/.bun/bin/bun"
command_args="build/index.js"
command_user="deploy:deploy"

pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.err"

depend() { need net; }

start_pre() {
  checkpath -f -m 0644 -o deploy:deploy "\$output_log" "\$error_log"
  export NODE_ENV="production"
  export PORT="3000"
  export HOST="0.0.0.0"
}

start() {
  ebegin "Starting \${RC_SVCNAME}"
  supervise-daemon "\${RC_SVCNAME}" \\
    -S \\
    -u "\${command_user}" \\
    -d "\${directory}" \\
    -1 "\${output_log}" \\
    -2 "\${error_log}" \\
    -p "\${pidfile}" \\
    -D 2 \\
    -m 0 \\
    -- \\
    "\${command}" \${command_args}
  eend \$?
}

stop() {
  ebegin "Stopping \${RC_SVCNAME}"
  supervise-daemon "\${RC_SVCNAME}" -K -p "\${pidfile}"
  eend \$?
}
EOF

  chmod +x "$SVC_FILE"
  rc-update add "$REPO_NAME" default >/dev/null 2>&1 || true
  rc-service "$REPO_NAME" restart >/dev/null 2>&1 || true
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
  # fail fast if app not reachable locally
  if ! curl -fsS -I http://127.0.0.1:3000 >/dev/null 2>&1; then
    echo "APP DOWN: cannot reach http://127.0.0.1:3000" >&2
    echo "---- /var/log/${REPO_NAME}.err ----" >&2
    tail -n 200 "/var/log/${REPO_NAME}.err" 2>/dev/null || true
    exit 1
  fi

  # fail fast if caddy not reachable locally
  if ! curl -fsS -I http://127.0.0.1 >/dev/null 2>&1; then
    echo "CADDY DOWN: cannot reach http://127.0.0.1" >&2
    rc-service caddy status || true
    exit 1
  fi

  echo "OK"
  echo "  app  : http://127.0.0.1:3000"
  echo "  proxy: http://127.0.0.1"
  echo "  live : https://${DOMAIN}"
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
  write_app_service
  write_caddyfile
  final_checks
}

main "$@"
