#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define base directory
WORK_DIR="$HOME/osrm"
OSM_FILE="ethiopia-latest.osm.pbf"
OSRM_BASE="ethiopia-latest.osrm"
PROFILE="/opt/car.lua"  # You can change this if needed

# Create the directory if it doesn't exist
mkdir -p "$WORK_DIR"

# Check if the OSM file exists
if [ ! -f "$WORK_DIR/$OSM_FILE" ]; then
  echo "❌ OSM file '$OSM_FILE' not found in '$WORK_DIR'. Please place it there before running the script."
  exit 1
fi

echo "🔧 Step 1: Extracting with car profile..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-extract -p "$PROFILE" "/data/$OSM_FILE"

echo "🧩 Step 2: Partitioning..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-partition "/data/$OSRM_BASE"

echo "🎛️ Step 3: Customizing..."
docker run -t -v "$WORK_DIR:/data" osrm/osrm-backend osrm-customize "/data/$OSRM_BASE"

echo "🚀 Step 4: Starting OSRM routing engine on port 5001..."
docker run -d -p 5001:5000 -v "$WORK_DIR:/data" osrm/osrm-backend osrm-routed --algorithm mld "/data/$OSRM_BASE"
