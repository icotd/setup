#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_FILES_DIR="$SCRIPT_DIR/custom_files"
OSM_DIR="$HOME/osm"
OSM_FILENAME="addis-ababa.osm.pbf"
CONTAINER_NAME="valhalla"
VALHALLA_IMAGE="ghcr.io/valhalla/valhalla-scripted:latest"
VALHALLA_PORT="${VALHALLA_PORT:-8002}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check if Docker is running
check_docker() {
  if ! docker info > /dev/null 2>&1; then
    log_error "Docker is not running. Please start Docker and try again."
    exit 1
  fi
}

# Check if required tools are installed
check_dependencies() {
  local missing=()
  
  if ! command -v docker &> /dev/null; then
    missing+=("docker")
  fi
  
  if ! command -v wget &> /dev/null; then
    missing+=("wget")
  fi
  
  if ! command -v osmium &> /dev/null; then
    log_warning "osmium not found. Install with: brew install osmium-tool (macOS) or apt-get install osmium-tool (Linux)"
    log_warning "The download script will still work, but extraction requires osmium."
  fi
  
  if [ ${#missing[@]} -ne 0 ]; then
    log_error "Missing required tools: ${missing[*]}"
    log_info "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
  fi
}

# Download OSM data
download_osm_data() {
  log_info "Downloading OSM data..."
  if [ -f "$SCRIPT_DIR/download_data.sh" ]; then
    bash "$SCRIPT_DIR/download_data.sh"
  else
    log_error "download_data.sh not found!"
    exit 1
  fi
}

# Prepare custom_files directory
prepare_custom_files() {
  log_info "Preparing custom_files directory..."
  mkdir -p "$CUSTOM_FILES_DIR"
  
  # Copy OSM file to custom_files if it exists
  if [ -f "$OSM_DIR/$OSM_FILENAME" ]; then
    log_info "Copying $OSM_FILENAME to custom_files..."
    cp "$OSM_DIR/$OSM_FILENAME" "$CUSTOM_FILES_DIR/"
    log_success "OSM file copied to custom_files"
  else
    log_warning "OSM file not found at $OSM_DIR/$OSM_FILENAME"
    log_info "You can manually place OSM .pbf files in $CUSTOM_FILES_DIR"
  fi
}

# Pull Docker image
pull_image() {
  log_info "Pulling Valhalla Docker image..."
  if docker pull "$VALHALLA_IMAGE" > /dev/null 2>&1; then
    log_success "Docker image pulled successfully"
  else
    log_error "Failed to pull Docker image"
    exit 1
  fi
}

# Stop existing container if running
stop_existing_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Stopping existing container..."
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
    log_success "Existing container removed"
  fi
}

# Start Valhalla container
start_container() {
  log_info "Starting Valhalla container..."
  
  # Environment variables for the container
  local env_vars=(
    -e "build_admins=True"
    -e "build_time_zones=True"
    -e "build_elevation=False"
    -e "build_transit=False"
    -e "build_tar=True"
    -e "serve_tiles=True"
    -e "update_existing_config=True"
  )
  
  # Start container
  docker run -dt \
    --name "$CONTAINER_NAME" \
    -p "${VALHALLA_PORT}:8002" \
    -v "${CUSTOM_FILES_DIR}:/custom_files" \
    "${env_vars[@]}" \
    "$VALHALLA_IMAGE" > /dev/null
  
  log_success "Container started: $CONTAINER_NAME"
  log_info "Container is building tiles (this may take a while)..."
  log_info "Check logs with: docker logs -f $CONTAINER_NAME"
}

# Wait for service to be ready
wait_for_service() {
  log_info "Waiting for Valhalla service to be ready..."
  local max_attempts=60
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if curl -s "http://localhost:${VALHALLA_PORT}/status" > /dev/null 2>&1; then
      log_success "Valhalla service is ready!"
      return 0
    fi
    
    attempt=$((attempt + 1))
    echo -n "."
    sleep 5
  done
  
  echo ""
  log_warning "Service did not become ready within expected time"
  log_info "Check container logs: docker logs $CONTAINER_NAME"
  return 1
}

# Show status
show_status() {
  echo ""
  log_info "=== Valhalla Status ==="
  
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_success "Container is running"
    echo "  Container: $CONTAINER_NAME"
    echo "  Port: http://localhost:${VALHALLA_PORT}"
    echo "  API: http://localhost:${VALHALLA_PORT}/route"
    echo "  Status: http://localhost:${VALHALLA_PORT}/status"
  else
    log_warning "Container is not running"
  fi
  
  echo ""
  log_info "=== Useful Commands ==="
  echo "  View logs:    docker logs -f $CONTAINER_NAME"
  echo "  Stop:         docker stop $CONTAINER_NAME"
  echo "  Start:        docker start $CONTAINER_NAME"
  echo "  Restart:      docker restart $CONTAINER_NAME"
  echo "  Remove:       docker rm -f $CONTAINER_NAME"
  echo ""
}

# Main setup function
main() {
  echo "🚀 Valhalla Docker Setup"
  echo "========================"
  echo ""
  
  check_docker
  check_dependencies
  download_osm_data
  prepare_custom_files
  pull_image
  stop_existing_container
  start_container
  
  echo ""
  log_info "Setup complete! Waiting for service to be ready..."
  wait_for_service
  show_status
}

# Run main function
main "$@"

