#!/usr/bin/env bash
set -euo pipefail

OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"          # ethiopia-latest.osm.pbf
BASE="${OSM_FILENAME%.osm.pbf}"                # ethiopia-latest
OSRM_BASE="${BASE}.osrm"                       # ethiopia-latest.osrm
OSRM_IMAGE="osrm/osrm-backend:latest"

mkdir -p "$OSRM_DIR"
cd "$OSRM_DIR"

# 1. Download extract
if [ ! -f "$OSM_FILENAME" ]; then
  echo "📥 Downloading $OSM_FILENAME …"
  wget -q --show-progress "$OSM_URL"
else
  echo "✅ OSM extract exists – skipping download"
fi

# 2. Extract
echo "🔧 osrm-extract …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua "/data/$OSM_FILENAME"

# 3. Partition
echo "🧩 osrm-partition …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/$OSRM_BASE"

# 4. Customise
echo "🎛️ osrm-customize …"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/$OSRM_BASE"

# 5. Run
echo "🚀 Launching OSRM on :5001 …"
docker run -d --rm --name osrm-ethiopia \
  -p 5001:5000 \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"
