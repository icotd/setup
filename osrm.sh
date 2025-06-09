#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
OSM_URL="http://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
OSM_FILE="ethiopia-latest.osm.pbf"
OSRM_BASE="ethiopia-latest.osrm"
PROFILE="/opt/car.lua"

echo "📥 Step 1: Downloading OSM extract from Geofabrik..."
wget -N "$OSM_URL"

echo "🔧 Step 2: Extracting with car profile..."
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-extract -p "$PROFILE" "/data/$OSM_FILE"

echo "🧩 Step 3: Partitioning..."
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-partition "/data/$OSRM_BASE"

echo "🎛️ Step 4: Customizing..."
docker run -t -v "${PWD}:/data" osrm/osrm-backend osrm-customize "/data/$OSRM_BASE"

# echo "🚀 Step 5: Starting OSRM routing engine on port 5001..."
docker run -d -p 5001:5000 -v "${PWD}:/data" osrm/osrm-backend osrm-routed --algorithm mld /data/ethiopia-latest.osrm

 
