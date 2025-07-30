# Supabase Deployment Analysis: Docker Compose vs Terraform Cloud.gov

## Executive Summary

This report analyzes the differences between the local development environment (Docker Compose) and the production deployment (Terraform on cloud.gov), highlighting architectural differences, best practices, and recommendations for maintaining parity between environments.

## Deployment Architectures

### Docker Compose (Local Development)
- **Purpose**: Local development and testing environment
- **Infrastructure**: Single machine with container orchestration
- **Networking**: Docker internal networks with port mapping
- **Database**: Self-managed PostgreSQL container
- **Storage**: Local filesystem for files
- **Scaling**: Vertical scaling within single machine
- **Access**: Direct port access (8000, 5432, etc.)

### Terraform Cloud.gov (Production)
- **Purpose**: Production-ready, compliant hosting
- **Infrastructure**: Cloud Foundry platform-as-a-service
- **Networking**: Cloud Foundry application routing with internal service mesh
- **Database**: Managed RDS PostgreSQL with high availability
- **Storage**: S3-compatible object storage with encryption
- **Scaling**: Horizontal scaling with multiple instances
- **Access**: Public routes through Cloud Foundry router

## Service-by-Service Comparison

### 1. API Gateway (Kong)

**Docker Compose:**
```yaml
kong:
  image: ghcr.io/GSA-TTS/supabase-kong:latest
  ports: ["8000:8000", "8443:8443"]
  environment:
    KONG_DATABASE: off
    KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
```

**Terraform:**
```hcl
module "kong" {
  source = "./kong"
  buildpack = ["apt-buildpack", "binary_buildpack"]
  memory = var.api_memory
  instances = var.api_instances
}
```

**Key Differences:**
- Docker: Native Kong container with volume-mounted config
- Terraform: Custom buildpack deployment with Cloud Foundry routing
- Docker: Direct port access
- Terraform: Routes through `*.app.cloud.gov` domains

### 2. Database Layer

**Docker Compose:**
```yaml
db:
  image: supabase/postgres:15.1.0.147
  ports: ["5432:5432"]
  volumes: ["db-data:/var/lib/postgresql/data"]
```

**Terraform:**
```hcl
module "database" {
  source = "github.com/GSA-TTS/terraform-cloudgov//database"
  rds_plan_name = var.database_plan
}
```

**Key Differences:**
- Docker: Self-managed container with local storage
- Terraform: Managed RDS with automated backups, patching, monitoring
- Docker: Single instance (development suitable)
- Terraform: High availability, redundant setup

### 3. PostgREST (REST API)

**Docker Compose:**
```yaml
rest:
  image: ghcr.io/GSA-TTS/supabase-postgrest:latest
  environment:
    PGRST_DB_URI: postgres://authenticator:${POSTGRES_PASSWORD}@db:5432/postgres
    PGRST_DB_SCHEMAS: public,storage,graphql_public
```

**Terraform:**
```hcl
resource "cloudfoundry_app" "supabase-rest" {
  docker_image = "${local.rest_image}@${data.docker_registry_image.rest.sha256_digest}"
  environment = {
    PGRST_DB_URI = local.rest_connection_string  # SSL required
    PGRST_JWT_SECRET = var.jwt_secret
  }
}
```

**Key Differences:**
- Docker: Direct database connection
- Terraform: SSL-enforced connection with service keys
- Docker: Container networking
- Terraform: Internal Cloud Foundry routing

### 4. Authentication (GoTrue)

**Docker Compose:**
```yaml
auth:
  image: ghcr.io/GSA-TTS/supabase-gotrue:latest
  environment:
    GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@db:5432/postgres
```

**Terraform:**
```hcl
# Currently commented out in terraform due to database role issues
# resource "cloudfoundry_app" "supabase-auth" { ... }
```

**Key Differences:**
- Docker: Fully functional with dedicated database user
- Terraform: Disabled due to Cloud.gov RDS role limitations

### 5. Storage Service

**Docker Compose:**
```yaml
storage:
  image: ghcr.io/GSA-TTS/supabase-storage-api:latest
  environment:
    STORAGE_BACKEND: file
    FILE_STORAGE_BACKEND_PATH: /var/lib/storage
```

**Terraform:**
```hcl
resource "cloudfoundry_app" "supabase-storage" {
  environment = {
    STORAGE_BACKEND = "s3"
    AWS_ACCESS_KEY_ID = cloudfoundry_service_key.s3.credentials.access_key_id
    STORAGE_S3_ENDPOINT = cloudfoundry_service_key.s3.credentials.fips_endpoint
  }
}
```

**Key Differences:**
- Docker: Local file storage
- Terraform: S3-compatible object storage with FIPS compliance
- Docker: Volume-mounted storage
- Terraform: Managed service with encryption and access controls

## Image Source Analysis

### Production Images Used in Terraform
```
ghcr.io/gsa-tts/cg-supabase/meta:scanned
ghcr.io/gsa-tts/cg-supabase/rest:scanned  
ghcr.io/gsa-tts/cg-supabase/storage:scanned
ghcr.io/gsa-tts/cg-supabase/studio:scanned
```

### Development Images Used in Docker Compose (TBD)
```
ghcr.io/GSA-TTS/supabase-postgres-meta:latest
ghcr.io/GSA-TTS/supabase-postgrest:latest
ghcr.io/GSA-TTS/supabase-storage-api:latest
ghcr.io/GSA-TTS/supabase-studio:latest
ghcr.io/GSA-TTS/supabase-gotrue:latest
ghcr.io/GSA-TTS/supabase-kong:latest
ghcr.io/GSA-TTS/supabase-realtime:latest
ghcr.io/GSA-TTS/supabase-edge-runtime:latest
ghcr.io/GSA-TTS/supabase-logflare:latest
ghcr.io/GSA-TTS/supabase-supavisor:latest
ghcr.io/GSA-TTS/supabase-imgproxy:latest
```

**Security Implications:**
- Both development and production now use the same upstream Supabase images
- Production uses scanned, approved images after CI/CD processing
- Development uses the latest tags, while production will use scanned versions
- CI/CD pipeline scans and republishes images weekly from `:latest` to `:scanned`

## Key Architectural Differences

### 1. Service Discovery and Networking

**Docker Compose:**
- Services communicate via service names (e.g., `http://rest:3000`)
- Docker internal DNS resolution
- Port-based communication

**Terraform Cloud.gov:**
- Services communicate via `*.apps.internal` domains
- Cloud Foundry service mesh
- Network policies control inter-service communication
- All communication on port 61443 (Cloud Foundry standard)

### 2. Secret Management

**Docker Compose:**
```bash
# .env file with plaintext secrets
POSTGRES_PASSWORD=your-super-secret-and-long-postgres-password
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
```

**Terraform Cloud.gov:**
```hcl
# Terraform variables (should use vault/secret manager)
variable "jwt_secret" {
  type        = string
  description = "JWT signing secret"
  sensitive   = true
}
```

### 3. SSL/TLS Configuration

**Docker Compose:**
- HTTP-only internal communication
- Optional HTTPS for external access
- No certificate management

**Terraform Cloud.gov:**
- Mandatory SSL for all external routes
- Platform-provided certificates
- SSL required for database connections

### 4. Health Checks and Monitoring

**Docker Compose:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
  interval: 30s
  timeout: 10s
```

**Terraform Cloud.gov:**
```hcl
health_check_type = "http"
health_check_http_endpoint = "/status"
```

## Security Considerations

### Docker Compose Security Gaps
1. **Plaintext secrets** in environment files
2. **No access controls** between services
3. **Local storage** without encryption
4. **No vulnerability scanning** of running containers
5. **Root access** to host system

### Terraform Cloud.gov Security Features
1. **Service-to-service network policies**
2. **Managed database** with encryption at rest
3. **FIPS-compliant** storage endpoints
4. **Scanned container images**
5. **Platform-level isolation**

## Configuration Parity Matrix

| Component | Docker Compose | Terraform Cloud.gov | Parity Level |
|-----------|----------------|---------------------|--------------|
| Kong Gateway | ✅ Native container | ✅ Buildpack deployment | High |
| PostgREST | ✅ Direct connection | ✅ SSL connection | High |
| Storage API | ⚠️ File backend | ✅ S3 backend | Medium |
| Studio UI | ✅ Full featured | ✅ Full featured | High |
| Auth Service | ✅ Working | ❌ Disabled | Low |
| Meta API | ✅ Working | ✅ Working | High |
| Realtime | ❌ Not deployed | ❌ Not deployed | Low |
| Edge Functions | ❌ Not deployed  | ❌ Not deployed | Low |
| Analytics | ❌ Not deployed  | ❌ Not deployed | Low |

## Best Practices for Maintaining Parity

### 1. Image Management
```bash
# Use consistent image sources between environments
# Docker Compose
image: ghcr.io/GSA-TTS/supabase-studio:latest

# Terraform (uses scanned version)
locals {
  studio_image = "ghcr.io/gsa-tts/cg-supabase/studio"
  studio_image_tag = "scanned"
}
```

### 2. Environment Variables
```yaml
# Standardize environment variable names
# Both environments should use identical variable names
PGRST_DB_SCHEMAS: "public,storage,graphql_public"
PGRST_JWT_SECRET: ${JWT_SECRET}
```

### 3. Configuration Management
```bash
# Use shared configuration files where possible
# Kong config should be identical in both environments
volumes:
  - ./volumes/api/kong.yml:/var/lib/kong/kong.yml:ro
```

### 4. Testing Strategy
```yaml
# Automated testing should verify parity
# Run identical test suites against both environments
test:
  - integration_tests
  - api_compatibility_tests
  - security_tests
```

## Recommendations

### Immediate Actions
1. **Enable Authentication Service** in Terraform by resolving database role issues
2. **Deploy Realtime Service** to Terraform for WebSocket functionality
3. **Add Edge Functions** support to Terraform deployment
4. **Implement secret management** for Terraform (HashiCorp Vault or cloud.gov service)

### Medium-term Improvements
1. **Continue using standardized image sources** - all services now use `ghcr.io/GSA-TTS/supabase-*:latest` upstream images
2. **Implement configuration drift detection** between environments
3. **Add SSL termination** to Docker Compose for dev/prod parity
4. **Create automated parity testing** in CI/CD pipeline

### Long-term Architecture Goals
1. **Infrastructure as Code** for both environments using Terraform
2. **GitOps deployment** pipeline with automatic drift correction
3. **Centralized logging and monitoring** across both environments
4. **Security policy enforcement** through automated scanning and compliance checks

## Monitoring and Observability Gaps

### Docker Compose
- Basic container health checks
- Docker logs collection
- No centralized monitoring
- Manual scaling decisions

### Terraform Cloud.gov
- Platform monitoring through Cloud.gov
- Application Performance Monitoring integration
- Automated scaling policies
- Centralized log aggregation

## Compliance Considerations

### Docker Compose (Development)
- ❌ No compliance controls
- ❌ No audit logging
- ❌ No access controls
- ❌ No encryption at rest

### Terraform Cloud.gov (Production)
- ✅ FedRAMP compliance
- ✅ Audit trail maintenance (logs.fr.cloud.gov)

## Cost Analysis

### Docker Compose
- **Infrastructure**: Local machine costs only
- **Maintenance**: Developer time for setup/maintenance
- **Scaling**: Limited to single machine resources

### Terraform Cloud.gov
- **Infrastructure**: Pay-per-use Cloud Foundry resources
- **Database**: Managed RDS costs
- **Storage**: S3 storage costs
- **Maintenance**: Reduced operational overhead

## Conclusion

The Docker Compose environment provides an excellent development experience with quick setup and full feature access. However, significant gaps exist between the development and production environments, particularly around:

1. **Service availability** (Auth, Realtime, Functions disabled in Terraform)
2. **Storage backends** (file vs S3)
3. **Security posture** (development vs production-grade)
4. **Networking architecture** (Docker networking vs Cloud Foundry)

To maintain development/production parity, the organization should prioritize:
1. Enabling all services in the Terraform deployment
2. Implementing proper secret management
3. Standardizing on scanned, approved container images
4. Creating automated parity testing

This will ensure that applications developed locally will work seamlessly when deployed to the production Cloud.gov environment.
