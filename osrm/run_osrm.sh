#!/usr/bin/env bash
set -euo pipefail

WORK="$(pwd)"

# sanity check on host
ls -lh "$WORK"/addis-ababa.osm.pbf "$WORK"/addis_speeds.csv "$WORK"/custom_car.lua

# sanity check inside container (files must appear here)
docker run --platform=linux/arm64/v8 --rm \
  -v "$WORK":/data ghcr.io/project-osrm/osrm-backend:v6.0.0 \
  sh -lc 'ls -lh /data && head -n2 /data/addis_speeds.csv; echo "ok"'

# EXTRACT (uses your CSV via profile)
docker run --platform=linux/arm64/v8 --rm -it \
  -v "$WORK":/data ghcr.io/project-osrm/osrm-backend:v6.0.0 \
  osrm-extract -p /data/custom_car.lua /data/addis-ababa.osm.pbf

# MLD partition + customize
docker run --platform=linux/arm64/v8 --rm -it \
  -v "$WORK":/data ghcr.io/project-osrm/osrm-backend:v6.0.0 \
  osrm-partition /data/addis-ababa.osrm

docker run --platform=linux/arm64/v8 --rm -it \
  -v "$WORK":/data ghcr.io/project-osrm/osrm-backend:v6.0.0 \
  osrm-customize /data/addis-ababa.osrm

# Serve
docker run --platform=linux/arm64/v8 --rm -it -p 5000:5000 \
  -v "$WORK":/data ghcr.io/project-osrm/osrm-backend:v6.0.0 \
  osrm-routed --algorithm mld /data/addis-ababa.osrm
