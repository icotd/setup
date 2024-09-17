#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="traefik_proxy"
DOMAIN="p.iqon.tech"
EMAIL="admin@p.iqon.tech"

# Cleanup any existing Traefik and Portainer containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."

# Stop and remove Traefik and Portainer containers if they exist
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

# Install ufw and allow required ports
sudo apt install ufw -y
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp  # Traefik dashboard
sudo ufw allow 9000/tcp  # Portainer
sudo ufw enable

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

# Create Docker Compose file for Traefik and Portainer
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

  portainer:
    image: portainer/portainer-ce
    command: -H unix:///var/run/docker.sock
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`portainer.$DOMAIN\`)"`
      - "traefik.http.routers.portainer.entrypoints=web,websecure"
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=lets-encrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
    ports:
      - "9000:9000"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - portainer_data:/data
    networks:
      - $NETWORK_NAME
    restart: always

volumes:
  portainer_data:

networks:
  $NETWORK_NAME:
    external: true
EOF

# Start Traefik and Portainer
echo "Starting Traefik and Portainer..."
cd $TRAEFIK_DIR
docker-compose up -d

echo "Setup complete. Access the Traefik dashboard at https://$DOMAIN:8080 and Portainer at https://portainer.$DOMAIN"
