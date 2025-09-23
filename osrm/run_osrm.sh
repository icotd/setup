#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"       # ethiopia-latest.osm.pbf
EXTRACT_FILENAME="addis-ababa.osm.pbf"
BASE="addis-ababa"
OSRM_BASE="${BASE}.osrm"
OSRM_IMAGE="ghcr.io/project-osrm/osrm-backend:v6.0.0"  # arm64-friendly
HOST_PORT=5001                                         # change if taken

# GitHub sources (raw)
GITHUB_USER="icotd"
REPO="setup"
BRANCH="main"
GH_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/${BRANCH}/osrm"
CSV_NAME="addis_speeds.csv"
LUA_NAME="custom_car.lua"

# === PREP ===
mkdir -p "$OSRM_DIR"
cd "$OSRM_DIR"

# 0) Tools sanity
command -v osmium >/dev/null 2>&1 || { echo "❌ 'osmium' not found. Install: brew install osmium-tool"; exit 1; }

# 1) Download PBF
if [ ! -f "$OSM_FILENAME" ]; then
  echo "📥 Downloading $OSM_FILENAME …"
  curl -L --fail -o "$OSM_FILENAME" "$OSM_URL"
else
  echo "✅ OSM extract exists – skipping download"
fi

# 2) Cut Addis Ababa bbox
if [ ! -f "$EXTRACT_FILENAME" ]; then
  echo "📦 Extracting Addis Ababa bbox to $EXTRACT_FILENAME …"
  osmium extract -b 38.525440,8.803691,38.987552,9.207208 \
    -o "$EXTRACT_FILENAME" \
    "$OSM_FILENAME"
else
  echo "✅ Addis Ababa extract exists – skipping"
fi

# 3) Fetch CSV + Lua from GitHub (always refresh to keep in sync)
echo "🌐 Fetching profile + speeds from GitHub …"
curl -L --fail -o "$CSV_NAME" "${GH_BASE}/${CSV_NAME}"
curl -L --fail -o "$LUA_NAME" "${GH_BASE}/${LUA_NAME}"

# 4) Sanity check on host & inside container
echo "🔍 Host files:"
ls -lh "$EXTRACT_FILENAME" "$CSV_NAME" "$LUA_NAME"
echo "🔍 Container view:"
docker run --platform=linux/arm64/v8 --rm -v "$PWD:/data" "$OSRM_IMAGE" \
  sh -lc 'ls -lh /data && echo "--- CSV head ---" && head -n2 /data/'"$CSV_NAME"'; echo "ok"'

# 5) Stop any existing server on same name/port
if docker ps --format '{{.Names}}' | grep -q '^osrm-server$'; then
  echo "🛑 Stopping existing osrm-server container …"
  docker stop osrm-server >/dev/null || true
  docker rm osrm-server >/dev/null || true
fi

# 6) Extract with custom profile (reads CSV internally)
echo "🔧 osrm-extract …"
docker run --platform=linux/arm64/v8 --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-extract -p "/data/$LUA_NAME" "/data/$EXTRACT_FILENAME"

# 7) MLD partition + customize
echo "🧩 osrm-partition …"
docker run --platform=linux/arm64/v8 --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/$OSRM_BASE"

echo "🎛️ osrm-customize …"
docker run --platform=linux/arm64/v8 --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/$OSRM_BASE"

# 8) Serve on HOST_PORT
echo "🚀 Launching OSRM on :$HOST_PORT …"
docker run -d --name osrm-server --restart unless-stopped \
  -p "$HOST_PORT:5000" -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"

echo "✅ OSRM up at http://localhost:${HOST_PORT}"

# 9) Smoke test (avg speed)
echo "🧪 Smoke test:"
curl -s "http://localhost:${HOST_PORT}/route/v1/driving/38.763,9.009;38.79,9.02?overview=false" \
| jq '.routes[0] | {distance_m: .distance, duration_s: .duration, kmh: ((.distance/1000)/(.duration/3600))}'
