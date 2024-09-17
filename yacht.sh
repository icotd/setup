#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="proxy"
DOMAIN="p.iqon.tech"
EMAIL="admin@p.iqon.tech"

# Cleanup any existing Traefik and Yacht containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."

# Stop and remove Traefik containers if they exist
docker-compose -f $TRAEFIK_DIR/docker-compose.yml down --volumes || true

# Remove the shared network if it exists
docker network rm $NETWORK_NAME || true

# Remove orphaned containers and volumes
docker system prune -a --volumes -f

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

# Create docker-compose.yml configuration file
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

  yacht:
    image: selfhostedpro/yacht
    container_name: yacht
    ports:
      - "8000:8000"  # Yacht UI
    volumes:
      - yacht:/config
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.yacht.entrypoints=web"
      - "traefik.http.routers.yacht.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.middlewares.yacht-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.yacht.middlewares=yacht-https-redirect"
      - "traefik.http.routers.yacht-secure.entrypoints=websecure"
      - "traefik.http.routers.yacht-secure.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.yacht-secure.tls=true"
      - "traefik.http.routers.yacht-secure.tls.certresolver=myresolver"
      - "traefik.http.services.yacht.loadbalancer.server.port=8000"
      - "traefik.docker.network=proxy"

volumes:
  yacht:
  letsencrypt:

networks:
  proxy:
    external: true
EOF

# Start Traefik and Yacht
echo "Starting Traefik and Yacht..."
docker-compose up -d

echo "Setup complete. Access the Traefik dashboard at https://$DOMAIN:8080 and Yacht at http://$DOMAIN:8000"
