#!/bin/sh
set -eu

# Usage examples
# chmod +x ./bootstrap-minio.sh
# ./bootstrap-minio.sh

# MINIO_USER='admin' \
# MINIO_PASS='your-strong-password' \
# MINIO_BUCKET='uploads' \
# MINIO_DATA_DIR='/data/minio' \
# ./bootstrap-minio.sh


MODE_LOCAL="${MODE_LOCAL:-1}"
MODE_NO_UI="${MODE_NO_UI:-1}"

MINIO_USER="${MINIO_USER:-admin}"
MINIO_PASS="${MINIO_PASS:-strong-password-change-me}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
MINIO_ALIAS="${MINIO_ALIAS:-local}"
MINIO_BUCKET="${MINIO_BUCKET:-my-bucket}"
MINIO_API_ADDR="${MINIO_API_ADDR:-127.0.0.1:9000}"

MINIO_BIN_DIR="${MINIO_BIN_DIR:-/usr/local/bin}"
MINIO_ETC_DIR="${MINIO_ETC_DIR:-/etc/minio}"
MINIO_ENV_FILE="${MINIO_ENV_FILE:-/etc/minio/minio.env}"
MINIO_LOG_FILE="${MINIO_LOG_FILE:-/var/log/minio/minio.log}"
MINIO_RUN_DIR="${MINIO_RUN_DIR:-/run/minio}"
MINIO_PID_FILE="${MINIO_PID_FILE:-/run/minio/minio.pid}"

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) MINIO_ARCH="linux-arm64" ;;
  x86_64|amd64) MINIO_ARCH="linux-amd64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

MINIO_URL="https://dl.min.io/server/minio/release/${MINIO_ARCH}/minio"
MC_URL="https://dl.min.io/client/mc/release/${MINIO_ARCH}/mc"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_pkg_if_missing() {
  pkg="$1"
  if ! apk info -e "$pkg" >/dev/null 2>&1; then
    apk add --no-cache "$pkg"
  fi
}

download_binary() {
  url="$1"
  name="$2"
  tmp="$(mktemp)"
  wget -qO "$tmp" "$url"
  install -m 0755 "$tmp" "${MINIO_BIN_DIR}/${name}"
  rm -f "$tmp"
}

ensure_dirs() {
  mkdir -p \
    "$MINIO_BIN_DIR" \
    "$MINIO_ETC_DIR" \
    "$MINIO_DATA_DIR" \
    "$(dirname "$MINIO_LOG_FILE")" \
    "$MINIO_RUN_DIR"
}

write_env_file() {
  cat > "$MINIO_ENV_FILE" <<EOF
MINIO_ROOT_USER='${MINIO_USER}'
MINIO_ROOT_PASSWORD='${MINIO_PASS}'
MINIO_VOLUMES='${MINIO_DATA_DIR}'
MINIO_OPTS='--address ${MINIO_API_ADDR}'
MINIO_BROWSER='off'
MINIO_LOG_FILE='${MINIO_LOG_FILE}'
MINIO_PID_FILE='${MINIO_PID_FILE}'
EOF
  chmod 600 "$MINIO_ENV_FILE"
}

write_openrc_service() {
  cat > /etc/init.d/minio <<'EOF'
#!/sbin/openrc-run

name="MinIO"
description="MinIO Community Edition object storage"

command="/usr/local/bin/minio"

depend() {
  need net
}

start_pre() {
  [ -f /etc/minio/minio.env ] || return 1
  . /etc/minio/minio.env

  checkpath -d -m 0755 -o root:root /run/minio
  checkpath -d -m 0755 -o root:root "$(dirname "$MINIO_LOG_FILE")"
  checkpath -d -m 0755 -o root:root "$MINIO_VOLUMES"
}

start() {
  . /etc/minio/minio.env
  export MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_BROWSER

  ebegin "Starting MinIO"
  start-stop-daemon \
    --start \
    --background \
    --make-pidfile \
    --pidfile "$MINIO_PID_FILE" \
    --stdout "$MINIO_LOG_FILE" \
    --stderr "$MINIO_LOG_FILE" \
    --exec "$command" -- server $MINIO_OPTS "$MINIO_VOLUMES"
  eend $?
}

stop() {
  . /etc/minio/minio.env

  ebegin "Stopping MinIO"
  start-stop-daemon --stop --pidfile "$MINIO_PID_FILE"
  eend $?
}
EOF
  chmod +x /etc/init.d/minio
}

wait_for_minio() {
  tries=60
  i=1

  while [ "$i" -le "$tries" ]; do
    if /usr/local/bin/mc alias set "$MINIO_ALIAS" "http://${MINIO_API_ADDR}" "$MINIO_USER" "$MINIO_PASS" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done

  echo "MinIO did not become ready in time." >&2
  echo "Check logs: $MINIO_LOG_FILE" >&2
  exit 1
}

ensure_bucket() {
  if /usr/local/bin/mc stat "${MINIO_ALIAS}/${MINIO_BUCKET}" >/dev/null 2>&1; then
    echo "Bucket already exists: ${MINIO_BUCKET}"
  else
    /usr/local/bin/mc mb "${MINIO_ALIAS}/${MINIO_BUCKET}"
    echo "Created bucket: ${MINIO_BUCKET}"
  fi
}

# add these functions before main()

stop_disable_service() {
  if [ -x /etc/init.d/minio ]; then
    rc-service minio stop >/dev/null 2>&1 || true
    rc-update del minio default >/dev/null 2>&1 || true
  fi
}

uninstall_all() {
  stop_disable_service

  rm -f /etc/init.d/minio
  rm -f "$MINIO_ENV_FILE"
  rm -f "${MINIO_BIN_DIR}/minio"
  rm -f "${MINIO_BIN_DIR}/mc"
  rm -f "$MINIO_PID_FILE"
  rm -f "$MINIO_LOG_FILE"

  rm -rf "$MINIO_RUN_DIR"
  rm -rf "$MINIO_ETC_DIR"
  rm -rf "$MINIO_DATA_DIR"

  rm -rf /root/.mc
  rm -rf /root/.minio
  rm -rf /var/lib/minio 2>/dev/null || true

  echo "MinIO completely removed"
}

# replace main() with this
main() {
  case "$ACTION" in
    uninstall)
      uninstall_all
      exit 0
      ;;
    install)
      ;;
    *)
      echo "Unsupported ACTION: $ACTION" >&2
      echo "Use ACTION=install or ACTION=uninstall" >&2
      exit 1
      ;;
  esac

  [ "$MODE_LOCAL" = "1" ] || { echo "Only MODE_LOCAL=1 is supported." >&2; exit 1; }
  [ "$MODE_NO_UI" = "1" ] || { echo "Only MODE_NO_UI=1 is supported." >&2; exit 1; }

  install_pkg_if_missing wget
  install_pkg_if_missing ca-certificates
  install_pkg_if_missing openrc

  ensure_dirs

  if ! need_cmd minio; then
    download_binary "$MINIO_URL" "minio"
  fi

  if ! need_cmd mc; then
    download_binary "$MC_URL" "mc"
  fi

  write_env_file
  write_openrc_service

  rc-update add minio default >/dev/null 2>&1 || true
  rc-service minio start >/dev/null 2>&1 || rc-service minio restart

  wait_for_minio
  ensure_bucket

  echo "Done"
  echo "Use:"
  echo "  rc-service minio status"
  echo "  rc-service minio start"
  echo "  rc-service minio restart"
  echo "  rc-service minio stop"
  echo "  mc ls ${MINIO_ALIAS}"
  echo
  echo "Uninstall:"
  echo "  ACTION=uninstall ./bootstrap-minio.sh"
}

main "$@"
