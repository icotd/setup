#!/bin/bash

# Become root user
sudo su

# Update package information and install required dependencies
apt update && apt install -y \
    ca-certificates \
    curl \
    gnupg \
    apt-transport-https \
    gpg

# Download GPG key and set up Docker's repository
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the package list to include the Docker repository
apt update -y

# Install Docker packages
apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-compose

# Verify Docker service status
systemctl is-active docker
