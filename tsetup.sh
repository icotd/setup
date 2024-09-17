#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="traefik_proxy"
DOMAIN="p.iqon.tech"
EMAIL="admin@p.iqon.tech"

# Cleanup any existing Traefik container, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."

# Stop and remove Traefik container if it exists
docker-compose -f $TRAEFIK_DIR/docker-compose.yml down --volumes || true

# Remove the shared network if it exists
docker network rm $NETWORK_NAME || true

# Remove orphaned containers and volumes
docker system prune --volumes -f

# Remove Traefik directory if it exists
rm -rf $TRAEFIK_DIR

# Update and install Docker and Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Create a shared Docker network
docker network create $NETWORK_NAME

# Create Traefik directory and configuration
mkdir -p $TRAEFIK_DIR
cd $TRAEFIK_DIR

# Create traefik.yml configuration file
cat <<EOF > traefik.yml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

api:
  dashboard: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: $EMAIL
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: DEBUG
EOF

# Create Docker Compose file for Traefik
cat <<EOF > docker-compose.yml
version: '3'

services:
  traefik:
    image: traefik:v2.5
    command:
      - "--api.insecure=true"
      - "--providers.docker"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.lets-encrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.lets-encrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.lets-encrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Traefik Dashboard
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./traefik.yml:/traefik.yml"
      - "./letsencrypt:/letsencrypt"
    networks:
      - $NETWORK_NAME
    restart: always

networks:
  $NETWORK_NAME:
    external: true
EOF

# Start Traefik
echo "Starting Traefik..."
docker-compose up -d

# Create a sample Docker Compose file for an example service (nginx)
cat <<EOF > $TRAEFIK_DIR/sample-service.yml
version: '3'

services:
  myapp:
    image: nginx:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(\`myapp.$DOMAIN\`)"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
    networks:
      - $NETWORK_NAME
    restart: always

networks:
  $NETWORK_NAME:
    external: true
EOF

# Start the sample service (myapp)
echo "Starting sample service (nginx)..."
docker-compose -f $TRAEFIK_DIR/sample-service.yml up -d

echo "Setup complete. Access the Traefik dashboard at http://localhost:8080"
echo "You can access your sample service at https://myapp.$DOMAIN"
