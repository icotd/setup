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
echo "🚀 Launching OSRM on port 5000…"
docker rm -f osrm-server >/dev/null 2>&1 || true
docker run -d \
  --name osrm-server \
  --restart unless-stopped \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"

echo "✅ OSRM server running → http://localhost:5000/route/v1/driving/…"
 

### ─────────────────────────────────────────────
### 8. Launch VROOM server on :5002
### ─────────────────────────────────────────────
echo "🚀 Launching VROOM on port 5000…"

docker run -dt --name vroom \
    --restart unless-stopped \
    --net host \  # or set the container name as host in config.yml and use --port 3000:3000 instead, see below
    -v $PWD/conf:/conf \ # mapped volume for config & log
    -e VROOM_ROUTER=osrm \ # routing layer: osrm, valhalla or ors
    ghcr.io/vroom-project/vroom-docker:v1.14.0

echo "✅ VROOM running → http://localhost:5000"

### ─────────────────────────────────────────────
### DONE
### ─────────────────────────────────────────────
echo ""
echo "🎉 OSRM + VROOM fully deployed!"
echo "   OSRM  : http://localhost:5001"
echo "   VROOM : http://localhost:5002"
echo ""
