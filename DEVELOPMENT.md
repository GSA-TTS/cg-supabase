# Supabase Development Environment

This directory contains a complete Docker Compose setup that mirrors the production Terraform deployment on cloud.gov. It provides a full-featured local development environment with all Supabase services.

## Quick Start

```bash
# Clone and setup
git clone [repository-url]
cd cg-supabase

# Setup environment (creates .env file and starts services)
./setup-dev.sh

# Access Supabase Studio
open http://localhost:8000
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
