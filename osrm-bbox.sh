#!/usr/bin/env bash
set -euo pipefail

OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"
EXTRACT_FILENAME="addis-ababa.osm.pbf"
BASE="addis-ababa"
OSRM_BASE="${BASE}.osrm"
OSRM_IMAGE="ghcr.io/project-osrm/osrm-backend:v6.0.0"

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
docker run --platform linux/amd64 --rm -t \
  -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua "/data/$EXTRACT_FILENAME"

# 4. osrm-partition
echo "🧩 osrm-partition …"
docker run --platform linux/amd64 --rm -t \
  -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/$OSRM_BASE"

# 5. osrm-customize
echo "🎛️ osrm-customize …"
docker run --platform linux/amd64 --rm -t \
  -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/$OSRM_BASE"

# 6. Launch OSRM server
echo "🚀 Setting up OSRM server"
docker run --platform linux/amd64 -d \
  --name osrm-server \
  --restart unless-stopped \
  -p 5000:5000 \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"

echo "🚀 OSRM server running at http://localhost:5000"

###############################################################
#                        VROOM SETUP                          #
###############################################################

echo "🚀 Setting up VROOM..."

mkdir -p ~/vroom/conf

cat > ~/vroom/conf/config.yml << 'EOF'
cliArgs:
  geometry: false
  planmode: false
  threads: 4
  explore: 5
  limit: "1mb"
  logdir: "/.."
  logsize: "100M"
  maxlocations: 1000
  maxvehicles: 200
  override: true
  path: ""
  port: 5001
  router: "osrm"
  timeout: 300000
  baseurl: "/"

routingServers:
  osrm:
    car:
      host: "0.0.0.0"
      port: "5000"
    bike:
      host: "0.0.0.0"
      port: "5000"
    foot:
      host: "0.0.0.0"
      port: "5000"
EOF

echo "✅ config.yml created at ~/vroom/conf/config.yml"

docker run --platform linux/amd64 -dt \
  --name vroom \
  --net host \
  -v ~/vroom/conf:/conf \
  -e VROOM_ROUTER=osrm \
  ghcr.io/vroom-project/vroom-docker:latest

echo "🚀 VROOM running at http://localhost:5001"
