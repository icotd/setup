#!/bin/bash

# Define variables
TRAEFIK_DIR=~/traefik
NETWORK_NAME="proxy"
DOMAIN="db.iqon.tech"
EMAIL="admin@p.iqon.tech"  # Change this to your actual email

# Function to check for command success
check_command() {
    if [ $? -ne 0 ]; then
        echo "$1"
        exit 1
    fi
}

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed, skipping installation."
else
    echo "Installing Docker and Docker Compose..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    check_command "Failed to download Docker installation script."
    
    sudo sh get-docker.sh
    check_command "Failed to install Docker."

    echo "Docker installed successfully."
fi

# Cleanup any existing Traefik and surrealist containers, networks, and volumes
echo "Cleaning up any existing containers, networks, and volumes..."
docker compose -f $TRAEFIK_DIR/docker-compose.yml down --volumes || true
docker network rm $NETWORK_NAME || true
docker system prune -a --volumes -f || true
rm -rf $TRAEFIK_DIR

# Create a shared Docker network
docker network create $NETWORK_NAME

# Clone the surrealist repository
git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }

# Build the Docker image
docker build -t surrealist .
check_command "Failed to build the Surrealist Docker image."

# Create Traefik directory and configuration
mkdir -p $TRAEFIK_DIR
cd $TRAEFIK_DIR

# Create traefik.yml configuration file
cat <<EOF > docker-compose.yml
version: '3.7'  # Add version for clarity
services:
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${EMAIL}"  # Use the variable
      - "--certificatesresolvers.myresolver.acme.storage=/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./acme.json:/acme.json"  # Ensure this file has the right permissions
    networks:
      - proxy
    restart: unless-stopped

  surrealist:
    image: surrealist
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.surrealist.rule=Host(\`$DOMAIN\`)"  # Use the variable
      - "traefik.http.services.surrealist.loadbalancer.server.port=8080"
      - "traefik.http.routers.surrealist.entrypoints=web,websecure"
      - "traefik.http.routers.surrealist.tls.certresolver=myresolver"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf

volumes:
  surrealist:
  letsencrypt:

networks:
  proxy:
    external: true
EOF

# Start Traefik and surrealist
echo "Starting Traefik and Surrealist..."
docker compose up -d

# Wait a few moments for Traefik to initialize
sleep 20

# Output URLs
echo "Setup complete. Access Surrealist at https://$DOMAIN"

# Verify Traefik logs for Let's Encrypt status
echo "Checking Traefik logs for certificate issuance..."
docker logs traefik | grep "Obtaining ACME certificate" || echo "No ACME certificate issuance found."

# Provide instructions for additional checks
echo "If you do not see 'Obtaining ACME certificate' in the logs, please check the following:"
echo "1. Ensure your domain DNS is correctly pointing to your server."
echo "2. Check for any errors in the Traefik logs related to certificate issuance."
echo "3. Verify that port 80 and 443 are open and accessible from the internet."
