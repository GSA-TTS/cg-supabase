
#!/bin/bash
set -e

# Supabase Local Development Setup Script
# Usage: source .env && ./setup-dev.sh

echo "[1/4] Exporting environment variables from .env..."
if [ -f .env ]; then
  source .env
else
  echo "No .env file found. Please create one from .env.example."
  exit 1
fi

echo "[2/4] Starting Docker Compose services..."
docker compose -f docker-compose.yml -f dev/docker-compose.dev.yml up -d

echo "[3/4] Waiting for containers to become healthy..."
docker compose -f docker-compose.yml -f dev/docker-compose.dev.yml ps


# Wait for all containers to be healthy (max 120s)
echo "[4/4] Waiting for all core services to be healthy..."
timeout=120
interval=5
elapsed=0
services=(supabase-db supabase-rest supabase-auth supabase-studio supabase-storage)
while true; do
  unhealthy=0
  for service in "${services[@]}"; do
    status=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null || echo "unknown")
    echo "$service: $status"
    if [[ "$status" != "healthy" ]]; then
      unhealthy=1
    fi
  done
  if [[ $unhealthy -eq 0 ]]; then
    echo "All core services are healthy!"
    break
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
  if [[ $elapsed -ge $timeout ]]; then
    echo "Timeout waiting for services to become healthy."
    break
  fi
done

echo "Setup complete! Access Supabase Studio at http://localhost:8000, Logs at http://localhost:4000, and Mail at http://localhost:9001."
