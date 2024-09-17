#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="proxy"
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
echo "Installing Docker and Docker Compose..."
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
cat <<EOF > docker-compose.yml
version: "3.8"
services:
  traefik:
    image: traefik:v2.9
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"        # The HTTP port
      - "443:443"      # The HTTPS port
      - "8080:8080"    # The dashboard port (optional, only for debugging purposes)
    volumes:
      - "./letsencrypt:/letsencrypt"  # Store certificates
      - "/var/run/docker.sock:/var/run/docker.sock"  # Traefik needs to access Docker
    networks:
      - proxy
    restart: unless-stopped

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9000:9000" # Portainer UI
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.entrypoints=web"
      - "traefik.http.routers.portainer.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.middlewares.portainer-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.portainer.middlewares=portainer-https-redirect"
      - "traefik.http.routers.portainer-secure.entrypoints=websecure"
      - "traefik.http.routers.portainer-secure.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.portainer-secure.tls=true"
      - "traefik.http.routers.portainer-secure.tls.certresolver=myresolver"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.docker.network=proxy"

volumes:
  portainer_data:
  letsencrypt:

networks:
  proxy:
    external: true
EOF

# Start Traefik and Portainer
echo "Starting Traefik and Portainer..."
docker-compose up -d

echo "Setup complete. Access the Traefik dashboard at https://$DOMAIN:8080 and Portainer at https://$DOMAIN"
