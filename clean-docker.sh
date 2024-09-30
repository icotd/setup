# Stop all running containers
docker stop $(docker ps -q)

# Remove all containers
docker rm $(docker ps -aq)

# Optional: Remove unused images
docker image prune -a

# Optional: Remove unused volumes
docker volume prune

# Optional: Remove all unused resources
docker system prune -a
