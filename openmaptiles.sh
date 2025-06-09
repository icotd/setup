#!/bin/bash

set -e

# Define and create the working directory
OPENMAPTILES_DIR="$HOME"
mkdir -p "$OPENMAPTILES_DIR"
cd "$OPENMAPTILES_DIR"

# Clone the OpenMapTiles repository if it doesn't exist
if [ ! -d "openmaptiles" ]; then
  echo "📦 Cloning OpenMapTiles repo..."
  git clone https://github.com/openmaptiles/openmaptiles.git
else
  echo "📁 'openmaptiles' repo already exists. Pulling latest changes..."
  cd openmaptiles
  git pull
fi

cd openmaptiles

# Pull required Docker images
echo "🐳 Pulling Docker images..."
docker compose pull || docker-compose pull

# Run quickstart for Ethiopia
echo "🧱 Generating Ethiopia vector tiles..."
./quickstart.sh ethiopia

# Check if tiles were created
MBTILES_FILE=$(find ./data -name "*.mbtiles" | head -n 1)
if [ ! -f "$MBTILES_FILE" ]; then
  echo "❌ Vector tiles not found. Tile generation likely failed."
  exit 1
fi

echo "✅ Done. Vector tiles for Ethiopia are in:"
echo "$MBTILES_FILE"

# Start TileServer-GL
echo "🚀 Starting TileServer-GL at http://localhost:8081 ..."
docker run --rm -it -v "$PWD/data:/data" -p 8081:80 maptiler/tileserver-gl
