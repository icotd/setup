#!/bin/bash

echo "Installing Colima..."
brew install colima

echo "Installing Docker..."
brew install docker

echo "Installing Docker Compose..."
brew install docker-compose

echo "Starting Colima with Docker runtime..."
colima start --runtime docker

# Note: brew services start colima is not necessary, as Colima runs as needed
# Uncomment the next line if you want to manage Colima as a service
# brew services start colima

echo "Setting DOCKER_HOST environment variable..."
echo 'export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock' >> ~/.bash_profile
echo 'export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock' >> ~/.zshrc

echo "Reloading shell configuration..."
source ~/.bash_profile
source ~/.zshrc

echo "Restarting colima..."
brew services restart colima

echo "Setup complete! You can verify with 'docker info'."
