#!/bin/bash

set -e

# Define working directory
OPENMAPTILES_DIR="$HOME"

# Remove and recreate working directory
if [ -d "$OPENMAPTILES_DIR/openmaptiles" ]; then
  rm -rf "$OPENMAPTILES_DIR/openmaptiles"
fi
 
cd "$OPENMAPTILES_DIR"

# Clone OpenMapTiles with submodules
echo "📦 Cloning latest OpenMapTiles repo (master)..."
git clone --recursive https://github.com/openmaptiles/openmaptiles.git
 
 sleep 10

 # ✅ Move into the repo directory before using docker-compose
cd openmaptiles

sleep 10
echo "🔄 Updating submodules..."
git submodule update --init --recursive

# Pull Docker images
echo "🐳 Pulling Docker images..."
docker compose pull || docker-compose pull

sleep 10
  
# Import Ethiopia data
# echo "🧱 Importing and preparing Ethiopia vector tiles..."
# make clean                  # clean / remove existing build files
# make                        # generate build files
# make start-db               # start up the database container.
# make import-data            # Import external data from OpenStreetMapData, Natural Earth and OpenStreetMap Lake Labels.
# make download area=ethiopia  # download albania .osm.pbf file -- can be skipped if a .osm.pbf file already existing
# make import-osm             # import data into postgres
# make import-wikidata        # import Wikidata
# make import-sql             # create / import sql functions 
# make generate-bbox-file     # compute data bbox -- not needed for the whole planet or for downloaded area by `make download`
# make  generate-tiles-pg      # generate tiles
 
# Generate tiles
echo "🎯 Generating tiles (zoom 14–19)..."
MIN_ZOOM=14 MAX_ZOOM=19 MBTILES_FILENAME=ethiopia.mbtiles ./quickstart.sh ethiopia

# Check output
MBTILES_FILE=$(find ./data -name "*.mbtiles" | head -n 1)
if [ ! -f "$MBTILES_FILE" ]; then
  echo "❌ Vector tiles not found. Tile generation likely failed."
  exit 1
fi

MBTILES_NAME="ethiopia.mbtiles"
MBTILES_FILE="data/$MBTILES_NAME"
MBTILES_BBOX_NAME="ethiopia.bbox"

# Confirm generation
if [ ! -f "$MBTILES_FILE" ]; then
  echo "❌ Vector tiles not found. Tile generation likely failed."
  exit 1
fi

echo "✅ Done. Vector tiles for Ethiopia are in:"
echo "$MBTILES_FILE"

# Serve tiles
echo "🚀 Starting TileServer-GL at http://localhost:8081 ..."
docker run --rm -it -v "$PWD/data:/data" -p 8081:80 maptiler/tileserver-gl "$MBTILES_NAME"


