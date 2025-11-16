#!/usr/bin/env bash
set -euo pipefail

### ─────────────────────────────────────────────
### SETTINGS
### ─────────────────────────────────────────────
OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"
EXTRACT_FILENAME="addis-ababa.osm.pbf"
BASE="addis-ababa"
OSRM_BASE="${BASE}.osrm"

OSRM_IMAGE="osrm/osrm-backend:latest"
VROOM_IMAGE="ghcr.io/vroom-project/vroom-docker:v1.14.0"
VROOM_DIR="$OSRM_DIR/vroom-conf"

# Addis Ababa bounding box
BBOX="38.525440,8.803691,38.987552,9.207208"

### ─────────────────────────────────────────────
### PREP
### ─────────────────────────────────────────────
mkdir -p "$OSRM_DIR" "$VROOM_DIR"
cd "$OSRM_DIR"

### ─────────────────────────────────────────────
### 1. Download Ethiopia PBF
### ─────────────────────────────────────────────
if [ ! -f "$OSM_FILENAME" ]; then
  echo "📥 Downloading Ethiopia extract…"
  wget -q --show-progress "$OSM_URL"
else
  echo "✅ Ethiopia PBF found — skipping download."
fi

### ─────────────────────────────────────────────
### 2. Extract Addis Ababa subregion
### ─────────────────────────────────────────────
if [ ! -f "$EXTRACT_FILENAME" ]; then
  echo "📦 Extracting Addis Ababa (bbox)…"
  osmium extract -b "$BBOX" -o "$EXTRACT_FILENAME" "$OSM_FILENAME"
else
  echo "✅ Addis Ababa extract exists — skipping."
fi

### ─────────────────────────────────────────────
### 3. OSRM Extract
### ─────────────────────────────────────────────
echo "🔧 Running osrm-extract…"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua "/data/$EXTRACT_FILENAME"

### ─────────────────────────────────────────────
### 4. OSRM Partition
### ─────────────────────────────────────────────
echo "🧩 Running osrm-partition…"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/$OSRM_BASE"

### ─────────────────────────────────────────────
### 5. OSRM Customize
### ─────────────────────────────────────────────
echo "🎛️ Running osrm-customize…"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/$OSRM_BASE"

### ─────────────────────────────────────────────
### 6. Launch OSRM server on :5001
### ─────────────────────────────────────────────
echo "🚀 Launching OSRM on port 5001…"
docker rm -f osrm-server >/dev/null 2>&1 || true
docker run -d \
  --name osrm-server \
  --restart unless-stopped \
  -p 5001:5000 \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"

echo "✅ OSRM server running → http://localhost:5001/route/v1/driving/…"

### ─────────────────────────────────────────────
### 7. Create VROOM config.yml
### ─────────────────────────────────────────────
echo "📝 Writing VROOM config.yml…"
cat > "$VROOM_DIR/config.yml" <<EOF
routers:
  osrm:
    host: host.docker.internal
    port: 5001
    profile: car
EOF

### ─────────────────────────────────────────────
### 8. Launch VROOM server on :5002
### ─────────────────────────────────────────────
echo "🚀 Launching VROOM on port 5002…"
docker rm -f vroom >/dev/null 2>&1 || true
docker run -d \
  --name vroom \
  --restart unless-stopped \
  -p 5002:3000 \
  -v "$VROOM_DIR:/conf" \
  -e VROOM_ROUTER=osrm \
  "$VROOM_IMAGE"

echo "✅ VROOM running → http://localhost:5002"

### ─────────────────────────────────────────────
### DONE
### ─────────────────────────────────────────────
echo ""
echo "🎉 OSRM + VROOM fully deployed!"
echo "   OSRM  : http://localhost:5001"
echo "   VROOM : http://localhost:5002"
echo ""
