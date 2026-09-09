# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## What This Repo Is

A Terraform module and Docker Compose environment for deploying Supabase on [cloud.gov](https://cloud.gov) (a Cloud Foundry-based PaaS). It publishes security-scanned container images to `ghcr.io/gsa-tts/cg-supabase` and uses them in both local development and production.

## Local Development Commands

The Docker Compose environment is for **local development and testing only** — it does not deploy to cloud.gov.

All commands run from the `docker/` directory:

```bash
# First-time setup
cp .env.example .env
# Edit .env with your secrets, then:
./setup.sh
docker compose -f docker-compose.yml -f ./dev/docker-compose.dev.yml up -d

# Teardown (removes volumes)
./reset.sh

# Useful management
docker compose ps
docker compose logs -f [service-name]
docker compose restart [service-name]
docker compose exec db psql -U postgres
docker compose exec db pg_isready -U postgres
```

Service endpoints after startup:
- Studio UI: http://localhost:8082
- API Gateway (Kong): http://localhost:8000
- Meta API: http://localhost:5555
- Mail (dev only): http://localhost:9000

## Terraform (Production Deployment)

The root `main.tf` calls the `./supabase` module targeting cloud.gov:

```bash
terraform init
terraform plan
terraform apply
```

Credentials go in `vars.auto.tfvars` (see `vars.auto.tfvars-example` for service-account auth, username/password auth, or CF CLI config fallback after `cf login --sso`). Uses the official `cloudfoundry` provider (`~> 1.18.0`) against `https://api.fr.cloud.gov`.

JWT secrets (`jwt_secret`, `anon_key`, `service_role_key`) are **optional** — Terraform auto-generates them via the `camptocamp/jwt` provider (`jwt_hashed_token` resource) and `hashicorp/random` if not provided.

### First-time setup — DB schema initialization

`terraform apply` deploys pg-meta with `scripts/db_schema_init.sql` loaded into its environment. On startup, pg-meta runs that idempotent SQL from inside the cloud.gov app network before starting the API server. This creates the roles, schemas, and migration-tracking tables that GoTrue and Storage expect.

### Smoke test

Use `scripts/cloudgov_smoke_test.sh` to run a live cloud.gov deployment check. It targets the current `cf target` or `CG_ORG`/`CG_SPACE`, uses sandbox-safe sizing, creates/reuses backing RDS and S3 services with the `cf` CLI, and reports PASS/FAIL for app startup plus Kong-routed endpoints. For PR branches, run the image workflow on the branch first; it publishes a branch tag such as `pr-update-terraform`, and the smoke test uses the current branch tag by default. Override with `CG_IMAGE_TAG=<tag>`. It destroys by default; use `CG_KEEP_ON_FAILURE=1` when diagnosing.

## Architecture

### Two Environments, Same Components

| Concern | Local (Docker Compose) | Production (cloud.gov) |
|---|---|---|
| Database | PostgreSQL container | cloud.gov `micro-psql` service |
| Storage | Local filesystem | S3 bucket |
| Networking | HTTP, localhost | HTTPS, Cloud Foundry routes |
| Images | Tagged `scanned` from ghcr.io | Same scanned images |

Production inter-service traffic uses `apps.internal:61443` for Cloud Foundry platform-managed c2c TLS. Every backend app is configured to listen on app port `8080` so Cloud Foundry's stable `61443 -> app:8080` proxy mapping works.

### Service Map

- **Kong** (`supabase/api.tf`) — API gateway with key-auth, basic-auth, CORS, ACL plugins. Defines consumers (`anon`, `service_role`, `dashboard`) and routes to all downstream services.
- **PostgREST** (`supabase/rest.tf`) — Auto-generates REST API from the PostgreSQL schema.
- **GoTrue / Auth** (`supabase/auth.tf`, `.docker/auth.Dockerfile`) — Authentication service.
- **Studio** (`supabase/studio.tf`, `.docker/studio.Dockerfile`) — Web dashboard for database management.
- **Storage** (`supabase/storage.tf`) — File upload/management.
- **Meta API** (`supabase/meta.tf`) — Database schema introspection.
- **Realtime** — WebSocket subscriptions to database changes.
- **Supavisor** — Connection pooling.
- **Vector** — Log shipping to analytics.

### Terraform Module Structure

```
main.tf                  # Root: calls ./supabase module
providers-managed.tf     # Cloud Foundry provider config
variables.tf             # Root-level secrets (cf_user, jwt_secret, etc.)
supabase/
  supabase.tf            # Core CF space, database, ASG setup
  api.tf                 # Kong gateway + plugin config
  auth.tf / rest.tf / storage.tf / studio.tf / meta.tf
  kong/                  # Kong-specific resources and prepare script
  variables.tf           # Module-level variables with defaults
```

### Container Images

Images are built and published via `.github/workflows/supabase-images.yml` (weekly + manual trigger). The workflow pulls upstream Supabase images, scans them with Trivy, and pushes tagged versions to `ghcr.io/gsa-tts/cg-supabase/*:scanned` for both `linux/amd64` and `linux/arm64`.

Custom Dockerfiles in `.docker/` extend the upstream auth and studio images.

### Database Initialization

SQL init scripts live in `docker/volumes/db/` and run automatically on first container start. Kong config is in `docker/volumes/api/`.
