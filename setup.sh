#!/bin/bash

# Define variables
CADDY_DIR=~/caddy
PORTAINER_DIR=~/portainer
EMAIL="admin@iqon.tech"
DOMAIN="p.iqon.tech"
NETWORK_NAME="bridge"

# Cleanup any existing containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."
docker-compose -f $CADDY_DIR/docker-compose.yml down --volumes || true
docker-compose -f $PORTAINER_DIR/docker-compose.yml down --volumes || true
docker system prune --volumes -f
rm -rf $CADDY_DIR
rm -rf $PORTAINER_DIR

# Update and install Docker and Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Create Caddy directory and Docker Compose configuration for Caddy with Docker plugin
mkdir -p $CADDY_DIR
cat <<EOF > $CADDY_DIR/docker-compose.yml
version: '3'

services:
  caddy:
    image: caddy:2.8.4-builder-alpine
    container_name: caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "caddy_data:/data"
      - "caddy_config:/config"
      - "/var/run/docker.sock:/var/run/docker.sock"  # To access Docker API
    environment:
      - CADDY_DOCKER_MODE=true
      - CADDY_DOCKER_NETWORK=$NETWORK_NAME
    networks:
      - $NETWORK_NAME
    restart: always

volumes:
  caddy_data:
  caddy_config:

networks:
  $NETWORK_NAME:
    external: true
EOF

# Create Portainer directory and Docker Compose configuration
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
    networks:
      - $NETWORK_NAME
    labels:
      - caddy=true
      - caddy.reverse_proxy.$DOMAIN=portainer:9000  # Reverse proxy for the specified domain
      - caddy.tls.email=$EMAIL  # SSL certificate for the domain
    restart: always

volumes:
  portainer_data:

networks:
  $NETWORK_NAME:
    external: true
EOF

# Start Caddy
echo "Starting Caddy..."
cd $CADDY_DIR
docker-compose up -d

# Start Portainer
echo "Starting Portainer..."
cd $PORTAINER_DIR
docker-compose up -d

echo "Setup complete. Caddy will automatically handle SSL and reverse proxy for Portainer at https://$DOMAIN."
