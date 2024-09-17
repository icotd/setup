#!/bin/bash

# Define variables
CADDY_DIR=~/caddy
PORTAINER_DIR=~/portainer
EMAIL="admin@iqon.tech"
DOMAIN="p.iqon.tech"
NETWORK_NAME="shared_network"

# Cleanup any existing Caddy, Portainer containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."

# Stop and remove Caddy and Portainer containers if they exist
docker-compose -f $CADDY_DIR/docker-compose.yml down --volumes || true
docker-compose -f $PORTAINER_DIR/docker-compose.yml down --volumes || true

# Remove the shared network if it exists
docker network rm $NETWORK_NAME || true

# Remove any orphaned containers and volumes
docker system prune --volumes -f

# Remove Caddy and Portainer directories if they exist
rm -rf $CADDY_DIR
rm -rf $PORTAINER_DIR

# Update and install Docker and Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Install ufw and allow required ports
sudo apt install ufw -y
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Create a shared Docker network
docker network create $NETWORK_NAME

# Create Caddy directory and configuration
mkdir -p $CADDY_DIR
cat <<EOF > $CADDY_DIR/Dockerfile
FROM caddy:2

COPY Caddyfile /etc/caddy/Caddyfile
EOF

# Create Caddy configuration file
cat <<EOF > $CADDY_DIR/Caddyfile
{
  email $EMAIL
}

$DOMAIN {
  reverse_proxy portainer:9000
}
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
    networks:
      - $NETWORK_NAME
    ports:
      - "9000:9000"
    restart: always

volumes:
  portainer_data:

networks:
  $NETWORK_NAME:
    external: true
EOF

# Create Caddy Docker Compose file
cat <<EOF > $CADDY_DIR/docker-compose.yml
version: '3'

services:
  caddy:
    build: .
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "./Caddyfile:/etc/caddy/Caddyfile"
      - "caddy_data:/data"
      - "caddy_config:/config"
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

# Start Caddy and Portainer
echo "Starting Caddy..."
cd $CADDY_DIR
docker-compose up -d

echo "Starting Portainer..."
cd $PORTAINER_DIR
docker-compose up -d

echo "Setup complete. Access Portainer at https://$DOMAIN"
