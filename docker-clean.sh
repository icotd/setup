#!/bin/bash

echo "⚠️ WARNING: This will delete all Docker containers, images, volumes, and networks."
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo "🛑 Stopping all running containers..."
docker ps -q | xargs -r docker stop

echo "🧹 Removing all containers..."
docker ps -aq | xargs -r docker rm -f

echo "🧼 Removing all images..."
docker images -aq | xargs -r docker rmi -f

echo "🧯 Removing all volumes..."
docker volume ls -q | xargs -r docker volume rm

echo "🔌 Removing all networks (except default)..."
docker network ls | grep -v "bridge\|host\|none" | awk '{print $1}' | xargs -r docker network rm

echo "🧽 Cleaning up unused data..."
docker system prune -af --volumes

# Optional: remove Colima VM (uncomment if desired)
# echo "🧨 Removing Colima VM..."
# colima delete

echo "✅ Docker environment is now clean."
