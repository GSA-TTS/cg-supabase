
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

echo "[4/4] Checking health of core services..."
for service in supabase-db supabase-rest supabase-auth supabase-studio supabase-analytics supabase-storage; do
  status=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null || echo "unknown")
  echo "$service: $status"
done

echo "Setup complete! Access Supabase Studio at http://localhost:8082 and Mail at http://localhost:9001."
