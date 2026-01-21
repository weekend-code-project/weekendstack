#!/bin/bash
# List all stopped or problematic containers

echo "Stopped or Problematic Containers:"
echo "=================================="
echo ""

docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v "Exited (0)"
docker ps -a --filter "status=created" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
docker ps -a --filter "status=dead" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo "To view logs for a container:"
echo "  docker logs <container-name>"
echo ""
echo "To restart a specific service:"
echo "  docker compose up -d <service-name>"
