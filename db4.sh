#!/bin/bash

# Define variables
SURREALIST_DIR=~/surrealist
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
# Stop and remove Traefik containers if they exist
docker compose -f $TRAEFIK_DIR/docker-compose.yml down --volumes || true

# Remove the shared network if it exists
docker network rm $NETWORK_NAME || true

# Remove orphaned containers and volumes
docker system prune -a --volumes -f

# Remove Traefik directory if it exists
rm -rf $TRAEFIK_DIR
 
# Clone the surrealist repository
git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git || { echo "Failed to clone surrealist repository"; exit 1; }
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }
 
# Build the Docker image
docker build -t surrealist .
check_command "Failed to build the Surrealist Docker image."
docker run -p 8080:8080 surrealist
