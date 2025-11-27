#!/usr/bin/env bash
set -euo pipefail

OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"            # ethiopia-latest.osm.pbf
EXTRACT_FILENAME="addis-ababa.osm.pbf"           # extracted file
BASE="addis-ababa"                               
OSRM_BASE="${BASE}.osrm"                         # addis-ababa.osrm
OSRM_IMAGE="project-osrm/osrm-backend:v6.0.0"

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
echo "🚀 Setting up OSRM server"
docker run -d \
  --name osrm-server \
  --restart unless-stopped \
  -p 5000:5000 \
  -v "$PWD:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld "/data/$OSRM_BASE"

echo "🚀 OSRM server running at http://localhost:5000 "

# 6. Launch the routing server
echo "🚀 Setting up VROOM "

# Create VROOM config directory
mkdir -p ~/vroom/conf

# Write config.yml
cat > ~/vroom/conf/config.yml << 'EOF'
cliArgs:
  geometry: false # retrieve geometry (-g)
  planmode: false # run vroom in plan mode (-c) if set to true
  threads: 4 # number of threads to use (-t)
  explore: 5 # exploration level to use (0..5) (-x)
  limit: "1mb" # max request size
  logdir: "/.." # the path for the logs relative to ./src
  logsize: "100M" # max log file size for rotation
  maxlocations: 1000 # max number of jobs/shipments locations
  maxvehicles: 200 # max number of vehicles
  override: true # allow cli options override (-c, -g, -t and -x)
  path: "" # VROOM path (if not in $PATH)
  port: 5001 # expressjs port
  router: "osrm" # routing backend (osrm, libosrm or ors)
  timeout: 300000 # milli-seconds
  baseurl: "/" #base url for api

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
  ors:
    driving-car:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    driving-hgv:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    cycling-regular:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    cycling-mountain:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    cycling-road:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    cycling-electric:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    foot-walking:
      host: "0.0.0.0/ors/v2"
      port: "8080"
    foot-hiking:
      host: "0.0.0.0/ors/v2"
      port: "8080"
  valhalla:
    auto:
      host: "0.0.0.0"
      port: "8002"
    bicycle:
      host: "0.0.0.0"
      port: "8002"
    pedestrian:
      host: "0.0.0.0"
      port: "8002"
    motorcycle:
      host: "0.0.0.0"
      port: "8002"
    motor_scooter:
      host: "0.0.0.0"
      port: "8002"
    taxi:
      host: "0.0.0.0"
      port: "8002"
    hov:
      host: "0.0.0.0"
      port: "8002"
    truck:
      host: "0.0.0.0"
      port: "8002"
    bus:
      host: "0.0.0.0"
      port: "8002"
EOF

echo "✅ config.yml created at ~/vroom/conf/config.yml"

docker run -dt \
  --name vroom \
  --net host \
  -v ~/vroom/conf:/conf \
  -e VROOM_ROUTER=osrm \
  ghcr.io/vroom-project/vroom-docker:latest

  echo "🚀 VROOM running at http://localhost:5001 "

  
