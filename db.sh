#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="proxy"
DOMAIN="db.iqon.tech"
EMAIL="admin@p.iqon.tech"

# Cleanup any existing Traefik and surrealist containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."

# Stop and remove Traefik containers if they exist
docker compose -f $TRAEFIK_DIR/docker-compose.yml down --volumes || true

# Remove the shared network if it exists
docker network rm $NETWORK_NAME || true

# Remove orphaned containers and volumes
docker system prune -a --volumes -f

# Remove Traefik directory if it exists
rm -rf $TRAEFIK_DIR

# Update and install Docker and Docker Compose
echo "Installing Docker and Docker Compose..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh 

# Create a shared Docker network
docker network create $NETWORK_NAME

git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }

# Build the Docker image
docker build -t surrealist .

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
    - "--certificatesresolvers.myresolver.acme.email=$EMAIL"
    ports:
      - "80:80"        # The HTTP port
      - "443:443"      # The HTTPS port
      # - "8080:8080"    # The dashboard port (disabled)
    volumes:
      - "./letsencrypt:/letsencrypt"  # Store certificates
      - "/var/run/docker.sock:/var/run/docker.sock"  # Traefik needs to access Docker
    networks:
      - proxy
    restart: unless-stopped

  surrealist:
    image: surrealist
    restart: unless-stopped
    networks:
      - proxy
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - ./config:/config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.surrealist.rule=Host(`db.$DOMAIN`)"
      - "traefik.http.services.surrealist.loadbalancer.server.port=8000"
      - "traefik.http.routers.surrealist.entrypoints=http"
      - "traefik.http.routers.surrealist.tls=true"
      - "traefik.http.routers.surrealist.tls.certresolver=myresolver"

volumes:
  surrealist:
  letsencrypt:

networks:
  proxy:
    external: true
EOF

# Start Traefik and surrealist
echo "Starting Traefik and surrealist..."
docker compose up -d

# Wait a few moments for Traefik to initialize
sleep 20

# Output URLs
echo "Setup complete. Access surrealist at https://$DOMAIN"

# Verify Traefik logs for Let's Encrypt status
echo "Checking Traefik logs for certificate issuance..."
docker logs traefik | grep "Obtaining ACME certificate" || echo "No ACME certificate issuance found."

# Provide instructions for additional checks
echo "If you do not see 'Obtaining ACME certificate' in the logs, please check the following:"
echo "1. Ensure your domain DNS is correctly pointing to your server."
echo "2. Check for any errors in the Traefik logs related to certificate issuance."
echo "3. Verify that port 80 and 443 are open and accessible from the internet."
