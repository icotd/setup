#!/bin/bash

# Clone the repository
git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git
cd surrealist || { echo "Directory 'surrealist' not found"; exit 1; }

# Build the Docker image
docker build -t surrealist .

# Create a docker-compose.yml file
cat <<EOF > docker-compose.yml
version: '3.8'  # Specify the version of Docker Compose

services:
  surrealist:
    image: surrealist
    restart: unless-stopped
    networks:
      - proxy
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - ./config:/config
    labels:
      - "traefik.http.services.surrealist.loadbalancer.server.scheme=http"
      - "traefik.http.services.surrealist.loadbalancer.server.port=8080"
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.surrealist-http.service=surrealist"
      - "traefik.http.routers.surrealist-http.rule=Host(\`db.\${DOMAIN}\`)"
      - "traefik.http.routers.surrealist-http.entrypoints=http"
      - "traefik.http.routers.surrealist.service=surrealist"
      - "traefik.http.routers.surrealist.rule=Host(\`db.\${DOMAIN}\`)"
      - "traefik.http.routers.surrealist.entrypoints=https"
      - "traefik.http.routers.surrealist.tls=true"
      - "traefik.http.routers.surrealist.tls.certresolver=myresolver"
      - "traefik.http.routers.surrealist.tls.domains[0].main=\${DOMAIN}"
      - "traefik.http.routers.surrealist.tls.domains[0].sans=*.\${DOMAIN}"

networks:
  proxy:
    external: true  # Assuming you have a Docker network named 'proxy'
EOF

echo "Docker Compose file created successfully."

# Start the service with Docker Compose
docker compose up -d

echo "Surrealist service is up and running with Traefik!"
