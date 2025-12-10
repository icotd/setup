#!/usr/bin/env bash
set -euo pipefail

OSRM_DIR="$HOME/osrm"
OSM_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="$(basename "$OSM_URL")"            # ethiopia-latest.osm.pbf
EXTRACT_FILENAME="addis-ababa.osm.pbf"           # extracted file
BASE="addis-ababa"
OSRM_IMAGE="osrm/osrm-backend:latest"
# Profiles to build: name|lua|port
PROFILES=(
  "car|/opt/car.lua|5000"
  "bike|/opt/bicycle.lua|5001"
  "foot|/opt/foot.lua|5002"
)

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

# 3-6. Build and launch OSRM for each profile (separate workspace per profile)
for entry in "${PROFILES[@]}"; do
  IFS='|' read -r PROFILE LUA PORT <<< "$entry"
  PROFILE_DIR="$PWD/osrm-$PROFILE"
  OSRM_BASE="${BASE}.osrm"

  mkdir -p "$PROFILE_DIR"
  cp -f "$PWD/$EXTRACT_FILENAME" "$PROFILE_DIR/$EXTRACT_FILENAME"

  echo "🔧 osrm-extract ($PROFILE)…"
  docker run --rm -t -v "$PROFILE_DIR:/data" "$OSRM_IMAGE" \
    osrm-extract -p "$LUA" "/data/$EXTRACT_FILENAME"

  echo "🧩 osrm-partition ($PROFILE)…"
  docker run --rm -t -v "$PROFILE_DIR:/data" "$OSRM_IMAGE" \
    osrm-partition "/data/$OSRM_BASE"

  echo "🎛️ osrm-customize ($PROFILE)…"
  docker run --rm -t -v "$PROFILE_DIR:/data" "$OSRM_IMAGE" \
    osrm-customize "/data/$OSRM_BASE"

  echo "🚀 Launching osrm-routed ($PROFILE) on port $PORT …"
  docker rm -f "osrm-server-$PROFILE" >/dev/null 2>&1 || true
  docker run -d \
    --name "osrm-server-$PROFILE" \
    --restart unless-stopped \
    -p "$PORT:5000" \
    -v "$PROFILE_DIR:/data" \
    "$OSRM_IMAGE" \
    osrm-routed --algorithm mld "/data/$OSRM_BASE"
done

echo "🚀 OSRM servers running:"
echo "  car  -> http://localhost:5000"
echo "  bike -> http://localhost:5001"
echo "  foot -> http://localhost:5002"

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
  port: 5003 # expressjs port
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
      port: "5001"
    foot:
      host: "0.0.0.0"
      port: "5002"
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

  
