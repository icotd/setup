#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
PORTAINER_DIR=~/portainer
EMAIL="admin@iqon.tech"
DOMAIN="apps.iqon.tech"

# Function to check the last command's success
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

echo "Installing Docker..."
# Install Docker using Docker's official convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
check_success "Docker installation failed."

echo "Installing Docker Compose..."
# Install Docker Compose
# Download Docker Compose binary for the appropriate OS and architecture
sudo curl -L "https://github.com/docker/compose/releases/download/v2.29.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# Make Docker Compose executable
sudo chmod +x /usr/local/bin/docker-compose
check_success "Docker Compose installation failed."

# Verify installations
docker --version
docker-compose --version

# Create Traefik directory and configuration
mkdir -p $TRAEFIK_DIR
cat <<EOF > $TRAEFIK_DIR/docker-compose.yml
version: '3'

services:
  traefik:
    image: traefik:v2.7
    command:
      - "--api.insecure=true"  # Enable Traefik dashboard (not recommended for production)
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=$EMAIL"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./letsencrypt:/letsencrypt"
    restart: always
EOF

# Create Portainer directory and configuration
mkdir -p $PORTAINER_DIR
cat <<EOF > $PORTAINER_DIR/docker-compose.yml
version: '3'

services:
  portainer:
    image: portainer/portainer-ce
    command: -H unix:///var/run/docker.sock
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "portainer_data:/data"
    ports:
      - "9000:9000"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=myresolver"
    restart: always

volumes:
  portainer_data:
EOF

# Start Traefik and Portainer
echo "Starting Traefik..."
cd $TRAEFIK_DIR
docker-compose up -d
check_success "Failed to start Traefik."

echo "Starting Portainer..."
cd $PORTAINER_DIR
docker-compose up -d
check_success "Failed to start Portainer."

echo "Setup complete. Access Portainer at https://$DOMAIN"
