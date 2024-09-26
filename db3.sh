#!/bin/bash

# Define variables
SURREALIST_DIR=~/surrealist
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

# Cleanup any existing surrealist containers and volumes
echo "Cleaning up any existing containers and volumes..."
docker compose -f $SURREALIST_DIR/docker-compose.yml down --volumes || true
rm -rf $SURREALIST_DIR

# Install Certbot for SSL management
sudo apt update -y
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d $DOMAIN

# Clone the surrealist repository
git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git || { echo "Failed to clone surrealist repository"; exit 1; }
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }

# Overwrite nginx.conf
curl -o nginx/nginx.conf https://raw.githubusercontent.com/icotd/setup/refs/heads/main/nginx.conf || { echo "Failed to download nginx.conf"; exit 1; }

# Build the Docker image
docker build -t surrealist .
check_command "Failed to build the Surrealist Docker image."

# Create Nginx configuration for Docker
cat <<EOF > docker-compose.yml
version: '3.7'
services:
  surrealist:
    image: surrealist
    restart: unless-stopped
    ports:
      - "8080:8080"  # HTTP (for internal use)
      - "8448:8448"  # HTTPS
    networks:
      - nginx_net

networks:
  nginx_net:
    driver: bridge
EOF

# Start the surrealist service
echo "Starting Surrealist..."
docker compose up -d

# Wait a few moments for Surrealist to initialize
sleep 20

# Output URL
echo "Setup complete. Access Surrealist at https://$DOMAIN"

# Provide instructions for additional checks
echo "If you encounter any issues, please check the following:"
echo "1. Ensure your domain DNS is correctly pointing to your server."
echo "2. Verify that ports 8448 (for HTTPS) and 8080 (if internally required) are open and accessible from the internet."
