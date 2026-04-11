#!/usr/bin/env bash
set -euo pipefail

# Alpine ARM64 MinIO + mc setup
# - installs wget if missing
# - installs minio server and mc client
# - binds MinIO to localhost only
# - disables MinIO UI
# - creates /data
# - starts MinIO in background
# - configures mc alias
# - creates bucket if missing

MINIO_USER="${MINIO_USER:-admin}"
MINIO_PASS="${MINIO_PASS:-strong-password}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data}"
MINIO_ADDR="${MINIO_ADDR:-127.0.0.1:9000}"
MINIO_ALIAS="${MINIO_ALIAS:-local}"
MINIO_BUCKET="${MINIO_BUCKET:-my-bucket}"
MINIO_LOG_FILE="${MINIO_LOG_FILE:-/var/log/minio.log}"

MINIO_URL="https://dl.min.io/server/minio/release/linux-arm64/minio"
MC_URL="https://dl.min.io/client/mc/release/linux-arm64/mc"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_pkg_if_missing() {
  local pkg="$1"
  if ! need_cmd "$pkg"; then
    apk add --no-cache "$pkg"
  fi
}

download_binary() {
  local url="$1"
  local out="$2"

  wget -qO "$out" "$url"
  chmod +x "$out"
  mv "$out" "/usr/local/bin/$out"
}

wait_for_minio() {
  local tries=30
  local i=1

  while [ "$i" -le "$tries" ]; do
    if mc alias set "$MINIO_ALIAS" "http://$MINIO_ADDR" "$MINIO_USER" "$MINIO_PASS" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done

  echo "MinIO did not become ready in time."
  echo "Check logs: $MINIO_LOG_FILE"
  exit 1
}

main() {
  install_pkg_if_missing wget

  mkdir -p /usr/local/bin
  mkdir -p "$MINIO_DATA_DIR"
  mkdir -p "$(dirname "$MINIO_LOG_FILE")"

  if ! need_cmd minio; then
    echo "Installing minio..."
    download_binary "$MINIO_URL" "minio"
  fi

  if ! need_cmd mc; then
    echo "Installing mc..."
    download_binary "$MC_URL" "mc"
  fi

  export MINIO_ROOT_USER="$MINIO_USER"
  export MINIO_ROOT_PASSWORD="$MINIO_PASS"
  export MINIO_BROWSER=off

  if pgrep -x minio >/dev/null 2>&1; then
    echo "MinIO is already running."
  else
    echo "Starting MinIO on $MINIO_ADDR ..."
    nohup minio server --address "$MINIO_ADDR" "$MINIO_DATA_DIR" >"$MINIO_LOG_FILE" 2>&1 &
  fi

  wait_for_minio

  if mc ls "$MINIO_ALIAS/$MINIO_BUCKET" >/dev/null 2>&1; then
    echo "Bucket already exists: $MINIO_BUCKET"
  else
    mc mb "$MINIO_ALIAS/$MINIO_BUCKET"
    echo "Created bucket: $MINIO_BUCKET"
  fi

  echo
  echo "Done."
  echo "MinIO endpoint: http://$MINIO_ADDR"
  echo "Alias: $MINIO_ALIAS"
  echo "Bucket: $MINIO_BUCKET"
  echo "Log: $MINIO_LOG_FILE"
  echo
  echo "Verify:"
  echo "  ss -tulpn | grep 9000 || netstat -tulpn 2>/dev/null | grep 9000"
  echo "  mc ls $MINIO_ALIAS"
}

main "$@"
