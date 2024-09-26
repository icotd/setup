#!/bin/bash

# Set default values for variables
BRANCH_NAME="feat/docker-image"
IMAGE_NAME="surrealist"
DOMAIN="${1:-iqon.tech}"  # Accept domain as the first argument, default to iqon.tech

# Clone the repository
git clone --branch "$BRANCH_NAME" https://github.com/Odonno/surrealist.git
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }

# Build the Docker image
docker build -t "$IMAGE_NAME" .

# Create a docker-compose.yml file
cat <<EOF > docker-compose.yml
version: '3.8'  # Specify the version of Docker Compose

services:
  surrealist:
    image: $IMAGE_NAME
    restart: unless-stopped
    networks:
      - proxy
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - ./config:/config
    labels:
      - "traefik.enable=true"
      - "traefik.http.services.$IMAGE_NAME.loadbalancer.server.scheme=http"
      - "traefik.http.services.$IMAGE_NAME.loadbalancer.server.port=8080"
      - "traefik.http.routers.$IMAGE_NAME-http.service=$IMAGE_NAME"
      - "traefik.http.routers.$IMAGE_NAME-http.rule=Host(\`db.$DOMAIN\`)"
      - "traefik.http.routers.$IMAGE_NAME-http.entrypoints=http"
      - "traefik.http.routers.$IMAGE_NAME.service=$IMAGE_NAME"
      - "traefik.http.routers.$IMAGE_NAME.rule=Host(\`db.$DOMAIN\`)"
      - "traefik.http.routers.$IMAGE_NAME.entrypoints=https"
      - "traefik.http.routers.$IMAGE_NAME.tls=true"
      - "traefik.http.routers.$IMAGE_NAME.tls.certresolver=myresolver"
      - "traefik.http.routers.$IMAGE_NAME.tls.domains[0].main=$DOMAIN"
      - "traefik.http.routers.$IMAGE_NAME.tls.domains[0].sans=*.$DOMAIN"

networks:
  proxy:
    external: true  # Assuming you have a Docker network named 'proxy'
EOF

echo "Docker Compose file created successfully."

# Start the service with Docker Compose
docker compose up -d

echo "Surrealist service is up and running with Traefik!"
