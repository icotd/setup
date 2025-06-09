#!/bin/bash
set -e

# Define constants
OSRM_DIR="$HOME/osrm"
OSM_URL="http://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILENAME="ethiopia-latest.osm.pbf"
OSM_FILE="$OSRM_DIR/$OSM_FILENAME"
OSRM_BASE="ethiopia-latest.osrm"
PROFILE="/opt/car.lua"  # Update this path if needed

# Resolve absolute path
OSRM_DIR_ABS="$(mkdir -p "$OSRM_DIR" && cd "$OSRM_DIR" && pwd)"

# Step 2: Download OSM file if missing
if [ ! -f "$OSM_FILE" ]; then
  echo "📥 Downloading OSM file using wget..."
  wget -O "$OSM_FILE" "$OSM_URL"
else
  echo "✅ OSM file already exists, skipping download."
fi

# Step 3: Extract
echo "🔧 Extracting with car profile..."
docker run -t -v "$OSRM_DIR_ABS:/data" osrm/osrm-backend osrm-extract -p "$PROFILE" "/data/$OSM_FILENAME"

# Step 4: Partition
echo "🧩 Partitioning..."
docker run -t -v "$OSRM_DIR_ABS:/data" osrm/osrm-backend osrm-partition "/data/$OSRM_BASE"

# Step 5: Customize
echo "🎛️ Customizing..."
docker run -t -v "$OSRM_DIR_ABS:/data" osrm/osrm-backend osrm-customize "/data/$OSRM_BASE"

# Step 6: Start routing engine
echo "🚀 Starting OSRM routing engine on port 5001..."
docker run -d -p 5001:5000 -v "$OSRM_DIR_ABS:/data" osrm/osrm-backend osrm-routed --algorithm mld "/data/$OSRM_BASE"
