#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define constants
WORK_DIR="$HOME/osrm"
OSM_URL="http://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILE="ethiopia-latest.osm.pbf"
OSRM_BASE="ethiopia-latest.osrm"
PROFILE="/opt/car.lua"  # Adjust if needed

# Step 1: Create working directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Step 2: Download the OSM file if it doesn't exist
if [ ! -f "$OSM_FILE" ]; then
  echo "📥 Downloading OSM file to $WORK_DIR..."
  curl -O "$OSM_URL"
else
  echo "✅ OSM file already exists, skipping download."
fi

# Step 3: Extract
echo "🔧 Extracting with car profile..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-extract -p "$PROFILE" "/data/$OSM_FILE"

# Step 4: Partition
echo "🧩 Partitioning..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-partition "/data/$OSRM_BASE"

# Step 5: Customize
echo "🎛️ Customizing..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-customize "/data/$OSRM_BASE"

# Step 6: Start OSRM routing engine
echo "🚀 Starting OSRM routing engine on port 5001..."
docker run -d -p 5001:5000 -v "$WORK_DIR:/data" osrm/osrm-backend osrm-routed --algorithm mld "/data/$OSRM_BASE"
