# Supabase Development Environment

This directory contains a complete Docker Compose setup that mirrors the production Terraform deployment on cloud.gov. It provides a full-featured local development environment with all Supabase services.

## Quick Start

```bash
# Clone and setup
git clone https://github.com/gsa-tts/cg-supabase.git
cd cg-supabase
cd docker

# Setup environment (creates .env file and starts services)
cp .env.example .env
source .env
./setup.sh # or manually run $docker compose -f docker-compose.yml -f ./dev/docker-compose.dev.yml up

# Access Supabase Studio
open http://localhost:8000
#See .env .env.example for username/password

./reset.sh  # Optional: Reset and remove the database and volumes
# or manually run $docker compose -f docker-compose.yml -f ./dev/docker-compose.dev.yml down 
```

## Architecture Overview

The development environment includes the core services that match the production Terraform deployment:

### Core Services (Terraform Production)
- **Kong Gateway** (port 8000) - API gateway and routing
- **PostgREST** - REST API from PostgreSQL  
- **Storage API** - File storage and management
- **Studio** - Web-based database management UI
- **Meta API** - Database metadata service
- **GoTrue** - Authentication service
- **PostgreSQL** - Core database (RDS in production)

## Service Endpoints

| Service | Development URL | Production Path | Terraform File |
|---------|-----------------|-----------------|----------------|
| Studio UI | http://localhost:8000 | `supabase${slug}.app.cloud.gov` | `studio.tf` |
| REST API | http://localhost:8000/rest/v1/ | `/rest/v1/` | `rest.tf` |
| Auth API | http://localhost:8000/auth/v1/ | `/auth/v1/` | `auth.tf` |
| Storage | http://localhost:8000/storage/v1/ | `/storage/v1/` | `storage.tf` |
| Database | localhost:5432 | RDS service | `supabase.tf` |

## Environment Configuration

The `.env` file contains all configuration variables that mirror the Terraform deployment:

```bash
# Core secrets (mirror terraform variables)
POSTGRES_PASSWORD=your-super-secret-and-long-postgres-password
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
ANON_KEY=eyJ... # Anonymous access key
SERVICE_ROLE_KEY=eyJ... # Service role key

# Database configuration (mirrors RDS in production)
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

# API Gateway (mirrors Kong deployment)
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443
SITE_URL=http://localhost:8000

# Service-specific configuration
PGRST_DB_SCHEMAS=public,storage,graphql_public
STORAGE_BACKEND=file  # S3 in production
SMTP_HOST=localhost   # External SMTP in production
```

## Development vs Production Differences

### Database
- **Development**: PostgreSQL container with local storage
- **Production**: Managed RDS with high availability and encryption

### Storage
- **Development**: Local file storage in `./volumes/storage`
- **Production**: S3-compatible object storage with FIPS compliance

### Networking
- **Development**: Docker internal networks
- **Production**: Cloud Foundry service mesh with network policies

### SSL/TLS
- **Development**: HTTP-only (optional HTTPS)
- **Production**: Mandatory SSL with platform certificates

### Images
- **Development**: Latest Supabase images from `ghcr.io/supabase/*:latest`
- **Production**: Scanned GSA-TTS images from `ghcr.io/gsa-tts/cg-supabase/*:scanned`

## Security Considerations

### Development Environment
- Uses default passwords and keys (change for any shared environment)
- No access controls between services  
- Local storage without encryption
- HTTP-only communication

### Production Environment  
- Managed secrets through Terraform variables
- Network policies control service communication
- Encrypted storage and databases
- HTTPS-only with proper certificates

## Management Commands

```bash
# Start all services
docker-compose up -d

# View service status
docker-compose ps

# View logs for specific service
docker-compose logs -f [service-name]

# Stop services
docker-compose stop

# Restart a specific service
docker-compose restart [service-name]

# Clean up (removes all data)
docker-compose down -v

# Pull latest images
docker-compose pull

# Build custom images
docker-compose build
```

## Troubleshooting

### Services Not Starting
```bash
# Check service health
docker-compose ps

# View detailed logs
docker-compose logs [service-name]

# Restart problematic service
docker-compose restart [service-name]
```

### Database Connection Issues
```bash
# Check database is running
docker-compose exec db pg_isready -U postgres

# Connect to database directly
docker-compose exec db psql -U postgres

# Reset database
docker-compose down -v
docker-compose up -d db
```

### Storage Issues
```bash
# Check storage directory permissions
ls -la volumes/storage

# Reset storage volume
docker-compose down
sudo rm -rf volumes/storage
mkdir -p volumes/storage
docker-compose up -d
```

## Custom Configuration

**Key Differences:**
- **Development mode** (`-f ./dev/docker-compose.dev.yml`): Includes sample data, mail testing server, and development-optimized settings
- **Production mode** (default): Only core infrastructure, no sample data, production-oriented configuration

### File Permissions Setup

**Important:** Docker containers need proper file permissions to read initialization scripts:

```bash
# Set proper permissions on all initialization files
cd docker
chmod 644 volumes/db/*.sql
chmod 644 dev/*.sql
chmod -R 755 volumes/
```

### Setup Commands

**Fresh Installation:**
```bash
cd docker
# Ensure proper permissions
chmod 644 volumes/db/*.sql dev/*.sql
chmod -R 755 volumes/

# Start with development overlay
docker compose -f docker-compose.yml -f dev/docker-compose.dev.yml up -d

# Check status
../test_supabase_health.sh
```

**Clean Restart (removes all data):**
```bash
cd docker
docker compose down -v  # Removes volumes and networks
chmod 644 volumes/db/*.sql dev/*.sql  # Reset permissions
docker compose -f docker-compose.yml -f dev/docker-compose.dev.yml up -d
```

### Service URLs

When running, services are accessible at:

- **Supabase Studio**: http://localhost:8082 (Web interface for database management)
- **API Gateway (Kong)**: http://localhost:8000 (All API endpoints)
- **Meta API**: http://localhost:5555 (Database metadata)
- **Analytics (Logflare)**: http://localhost:4000 (Logging dashboard)
- **Mail Interface**: http://localhost:9000 (Email testing)

## Debug and Troubleshooting

### Common Issues and Solutions

#### 1. Container Permission Errors

**Symptoms:** Containers fail to start with permission denied errors
```bash
# Fix file permissions
cd docker
chmod 644 volumes/db/*.sql dev/*.sql
chmod -R 755 volumes/ dev/
docker compose restart
```

#### 2. Database Authentication Failures

**Symptoms:** Services can't connect to database, password authentication failed
```bash
# Run manual database fixes
cd docker
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -f /docker-entrypoint-initdb.d/debug_manual_fixes.sql
# Or manually fix passwords
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -c "
ALTER USER supabase_auth_admin PASSWORD 'your-super-secret-and-long-postgres-password';
ALTER USER supabase_storage_admin PASSWORD 'your-super-secret-and-long-postgres-password';
"
```

#### 3. Missing Database Schemas

**Symptoms:** Auth or realtime services failing with "schema does not exist"
```bash
# Create missing schemas manually
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -c "
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO postgres, anon, authenticated, service_role, supabase_auth_admin;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;
"

# Create realtime schema
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -c "
CREATE SCHEMA IF NOT EXISTS realtime;
GRANT USAGE ON SCHEMA realtime TO postgres, anon, authenticated, service_role;
"

# Restart affected services
docker restart supabase-auth realtime-dev.supabase-realtime
```

#### 4. Analytics Database Missing

**Symptoms:** Analytics service fails, "_supabase database does not exist"
```bash
# Create analytics database and schema
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -c "
CREATE DATABASE _supabase;
"
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -d _supabase -c "
CREATE SCHEMA IF NOT EXISTS _analytics;
"
docker restart supabase-analytics
```

#### 5. Kong Configuration File Access

**Symptoms:** Kong failing with "can't open temp.yml: Permission denied"
```bash
# Fix Kong configuration permissions
cd docker
chmod -R 755 volumes/
find volumes/ -type f -exec chmod 644 {} \;
docker restart supabase-kong
```

### Debug Commands

**Check container status:**
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**View service logs:**
```bash
docker logs supabase-auth
docker logs supabase-kong  
docker logs supabase-db
docker logs supabase-analytics
```

**Connect to database:**
```bash
docker exec -e PGPASSWORD=postgres -it supabase-db psql -U postgres
```

**Run health check:**
```bash
cd /path/to/cg-supabase
./test_supabase_health.sh
```

**Manual SQL fixes (if automatic initialization fails):**
```bash
# Run comprehensive debug script
docker exec -e PGPASSWORD=postgres supabase-db psql -U postgres -f /docker-entrypoint-initdb.d/debug_manual_fixes.sql
```

### Expected HTTP Status Codes

When testing endpoints, these responses are **normal**:
- **HTTP 401 (Unauthorized)**: API endpoints require authentication keys
- **HTTP 400 (Bad Request)**: Some endpoints need specific headers  
- **HTTP 404 (Not Found)**: Some health check endpoints don't exist
- **HTTP 200 (OK)**: Successful responses

Only **connection failures** and **500 errors** indicate actual problems.
## TODO

- Deploy Kong as the API gateway in front of everything else
- Allow injection of the bucket and postgres db in place of the module creating/managing them itself
- Uncomment the `Deployment Architecture` section in this doc and make the diagram accurate

### Adding Custom Functions
```bash
# Add functions to the functions directory
mkdir -p volumes/functions/my-function
echo 'export default function handler(req) { return new Response("Hello!"); }' > volumes/functions/my-function/index.ts

# Restart functions service
docker-compose restart functions
```

### Custom Kong Configuration
Edit `volumes/api/kong.yml` to add custom routes or plugins:

```yaml
services:
  - name: my-service
    url: http://my-backend:3000
    routes:
      - name: my-route
        paths: ["/my-api/"]
    plugins:
      - name: cors
```

### Database Migrations
```bash
# Run migrations
docker-compose exec db psql -U postgres -f /path/to/migration.sql

# Create database dump
docker-compose exec db pg_dump -U postgres > backup.sql

# Restore database
docker-compose exec -T db psql -U postgres < backup.sql
```

## Production Deployment Reference

This development environment mirrors the production Terraform deployment. Key Terraform files:

- `main.tf` - Root module calling supabase module
- `supabase/supabase.tf` - Core infrastructure (database, networking)
- `supabase/api.tf` - Kong gateway configuration  
- `supabase/rest.tf` - PostgREST service
- `supabase/storage.tf` - Storage service with S3
- `supabase/studio.tf` - Supabase Studio UI
- `supabase/meta.tf` - Database metadata service
- `supabase/auth.tf` - Authentication service (disabled)

## CI/CD Integration

The GitHub Actions workflow in `.github/workflows/supabase-consolidated.yml` handles:

- Pulling all Supabase images weekly
- Scanning for security vulnerabilities
- Publishing scanned images to `ghcr.io/gsa-tts/cg-supabase/*`
- Updating production deployments

## Contributing

1. Test changes in the development environment first
2. Ensure parity with production Terraform configuration
3. Update this README when adding new services
4. Scan any new images for security vulnerabilities

## Support

- [Supabase Self-Hosting Documentation](https://supabase.com/docs/guides/self-hosting/docker)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Project Issues](https://github.com/GSA-TTS/cg-supabase/issues)
