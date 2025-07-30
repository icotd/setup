#!/usr/bin/env bash
set -euo pipefail

OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"            # ethiopia-latest.osm.pbf
EXTRACT_FILENAME="addis-ababa.osm.pbf"           # extracted file
BASE="addis-ababa"                               
OSRM_BASE="${BASE}.osrm"                         # addis-ababa.osrm
OSRM_IMAGE="osrm/osrm-backend:latest"

mkdir -p "$OSRM_DIR"
cd "$OSRM_DIR"

# 1. Download full Ethiopia if needed
if [ ! -f "$OSM_FILENAME" ]; then
  echo "📥 Downloading $OSM_FILENAME …"
  wget -q --show-progress "$OSM_URL"
else
  echo "✅ OSM extract exists – skipping download"
fi

# 2. Extract Addis Ababa from full Ethiopia file
if [ ! -f "$EXTRACT_FILENAME" ]; then
  echo "📦 Extracting Addis Ababa bbox to $EXTRACT_FILENAME …"
  osmium extract -b 38.525440,8.803691,38.987552,9.207208 \
    -o "$EXTRACT_FILENAME" \
    "$OSM_FILENAME"
else
  echo "✅ Addis Ababa extract exists – skipping"
fi

# 3. osrm-extract
echo "🔧 osrm-extract …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua "/data/$EXTRACT_FILENAME"

# 4. osrm-partition
echo "🧩 osrm-partition …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/$OSRM_BASE"

# 5. osrm-customize
echo "🎛️ osrm-customize …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/$OSRM_BASE"

# 6. Launch the routing server
echo "🚀 Launching OSRM for Addis Ababa on :5001 …"
docker run -d --rm --name osrm-server --restart unless-stopped \
  -p 5001:5000 \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"
