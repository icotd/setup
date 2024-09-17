#!/bin/bash

# Define variables
CADDY_DIR=~/caddy
PORTAINER_DIR=~/portainer
EMAIL="admin@iqon.tech"
DOMAIN="p.iqon.tech"
NETWORK_NAME="caddy_network"

# Cleanup any existing containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."
docker-compose -f $CADDY_DIR/docker-compose.yml down --volumes || true
docker-compose -f $PORTAINER_DIR/docker-compose.yml down --volumes || true
docker network rm $NETWORK_NAME || true
docker system prune -a --volumes -f
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

# Create user-defined network
echo "Creating user-defined Docker network: $NETWORK_NAME"
docker network create $NETWORK_NAME

# Create Caddy directory and Docker Compose configuration for Caddy
mkdir -p $CADDY_DIR
cat <<EOF > $CADDY_DIR/docker-compose.yml
version: '3'

services:
  caddy:
    image: caddy:2
    container_name: caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"  # Access Docker API
      - "caddy_data:/data"
      - "caddy_config:/config"
    networks:
      - caddy_network
    restart: always

volumes:
  caddy_data:
  caddy_config:

networks:
  caddy_network:
    external: true
EOF

# Create Caddyfile configuration
cat <<EOF > $CADDY_DIR/Caddyfile
{
  email $EMAIL
  acme_ca https://acme-v02.api.letsencrypt.org/directory
}

$DOMAIN {
  reverse_proxy portainer:9000
}
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
      - caddy_network
    labels:
      - caddy=true
      - caddy.reverse_proxy.$DOMAIN=portainer:9000  # Reverse proxy for the specified domain
      - caddy.tls.email=$EMAIL  # SSL certificate for the domain
    restart: always

volumes:
  portainer_data:

networks:
  caddy_network:
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
