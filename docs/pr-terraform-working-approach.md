# PR: Port Working cloud.gov Deployment Approach

## Summary

This PR ports Terraform patterns proven in live Supabase deployments on
cloud.gov into this repository. It enables the auth service, fixes multiple
service configuration bugs, adds Terraform-managed JWT generation, and aligns
SSL/TLS behavior with cloud.gov RDS in AWS GovCloud.

The branch has evolved in response to review feedback: the original custom JWT
script, manual database-prep script, and disabled Node.js certificate validation
have been removed.

---

## What Changed and Why

### 1. Auth service enabled (`supabase/auth.tf`)

The `cloudfoundry_app.supabase-auth` resource was previously commented out. It
is now configured and deployed using the GSA-TTS scanned GoTrue image:

- Image: `ghcr.io/gsa-tts/cg-supabase/auth:scanned`
- Private CF route: `supabase-auth<slug>.apps.internal:61443` for callers, routed to app port `8080`
- `GOTRUE_DB_DATABASE_URL` uses a dedicated database service key with
  `search_path=auth&sslmode=prefer`
- `GOTRUE_SITE_URL` and `API_EXTERNAL_URL` point to the Kong public gateway URL
- JWT, signup, and email defaults are configured for the deployed service

### 2. Kong routes and network policy fixed (`supabase/api.tf`)

Kong now routes to the deployed Supabase backend services over CF internal
routes and has network policy access to them.

Key fixes:

- Enables Kong to reach GoTrue for `/auth/v1/*`
- Uses generated or provided anon/service-role keys in the Kong declarative
  config
- Protects Studio through Kong basic-auth with a generated dashboard password
- Replaces stale Docker Compose hostnames for disabled services with commented
  CF-internal placeholders
- Leaves Realtime, Edge Functions, and Analytics routes commented out because
  those services are not deployed by this Terraform module

### 3. Terraform-managed JWT secrets (`supabase/supabase.tf`, `supabase/variables.tf`)

Previously, `jwt_secret`, `anon_key`, and `service_role_key` had to be supplied
by the caller. They are now optional. When omitted:

- `jwt_secret` is generated with `random_password`
- `anon_key` and `service_role_key` are generated with the `camptocamp/jwt`
  Terraform provider
- The generated keys are wired into GoTrue, PostgREST, Storage, Studio, and Kong

Callers can still provide explicit values when they need to preserve an existing
deployment's JWT material.

### 4. SSL/TLS handling corrected across services

cloud.gov RDS requires SSL and uses the AWS GovCloud RDS trust chain. The final
branch no longer disables Node.js TLS certificate verification.

| Runtime or path | Approach |
|---|---|
| pg-meta | Uses `PG_META_DB_SSL_MODE=require`; pg-meta's own variable is required because node-postgres ignores libpq `PGSSLMODE` |
| Studio table/SQL editor | Embeds `?sslmode=require` in `POSTGRES_DB` because Studio constructs the per-request PostgreSQL URL from `POSTGRES_*` variables |
| Node.js services | Startup command builds a CA bundle from CF platform certs plus the vendored AWS GovCloud RDS CA bundle, then exports `NODE_EXTRA_CA_CERTS` so node-postgres can validate the RDS certificate chain |
| Go/libpq-style service URLs | Keep the working `sslmode=prefer` connection strings used by the live deployment |

The reviewer-blocking `NODE_TLS_REJECT_UNAUTHORIZED=0` approach has been
removed from the Terraform configuration.

### 5. Meta service (`supabase/meta.tf`)

- Switched to GSA-TTS scanned image (`ghcr.io/gsa-tts/cg-supabase/meta:scanned`)
- Uses individual `PG_META_DB_HOST`, `PG_META_DB_PORT`, `PG_META_DB_NAME`,
  `PG_META_DB_USER`, and `PG_META_DB_PASSWORD` variables expected by newer
  pg-meta images
- Uses `PG_META_DB_SSL_MODE=require` rather than ineffective `PGSSLMODE`
- Runs idempotent database schema initialization before starting pg-meta
- Exports `NODE_EXTRA_CA_CERTS` at startup for RDS certificate validation

### 6. Storage service (`supabase/storage.tf`)

- Uses the GSA-TTS scanned storage image
- Adds `DB_SEARCH_PATH=storage,public,extensions`
- Adds single-tenant configuration (`IS_MULTITENANT=false`,
  `TENANT_ID=default-tenant`)
- Adds `GLOBAL_S3_*` variables alongside `STORAGE_S3_*` for compatibility with
  different storage-api versions
- Uses the cloud.gov S3 service key FIPS endpoint for the primary S3 backend
- Exports `NODE_EXTRA_CA_CERTS` at startup for RDS certificate validation

### 7. Studio service (`supabase/studio.tf`)

- Fixes `SUPABASE_URL`, which previously pointed back to Studio itself. It now
  points to the PostgREST internal route for server-side calls
- Adds `SUPABASE_PUBLIC_URL` for browser-side calls through Kong
- Fixes `POSTGRES_PASSWORD` to use Studio's own database service key
- Adds all `POSTGRES_*` variables required for Studio's schema browser and SQL
  editor
- Embeds `?sslmode=require` in `POSTGRES_DB` for the pg-meta per-request DB path
- Sets `NEXT_ANALYTICS_BACKEND_PROVIDER=bigquery` to avoid Studio's unsupported
  direct Postgres analytics path
- Adds Studio to PostgREST and Studio to pg-meta CF network policies
- Uses a port health check and larger disk quota that match the scanned image's
  runtime behavior

### 8. Provider authentication options (`providers-managed.tf`, `variables.tf`)

The root Cloud Foundry provider now supports the authentication modes exposed by the official `cloudfoundry/cloudfoundry` provider (`~> 1.18.0`):

- Service account: `cf_client_id` + `cf_client_secret`, recommended for CI/CD
- Username/password: `cf_user` + `cf_password`, retained for legacy workflows
- CF CLI config fallback: run `cf login -a https://api.fr.cloud.gov --sso` and leave the credential variables empty for interactive SSO workflows

Empty string variables are converted to `null` before reaching the provider so unused authentication modes do not block the selected mode.

### 9. Database schema initialization (`supabase/supabase.tf`, `supabase/meta.tf`)

The original branch used a manual `cloudgov_db_prep.sh` script, then briefly used
a Terraform `local-exec` provisioner. Both approaches were removed.

The current implementation loads `scripts/db_schema_init.sql` into Terraform and
runs it inside the pg-meta container before the pg-meta server starts. This works
from inside the cloud.gov app network and avoids requiring the operator machine
to reach the RDS endpoint directly.

Keeping the SQL in `scripts/db_schema_init.sql` avoids duplicating a large SQL
heredoc in Terraform while preserving infrastructure-managed initialization.

### 10. Removed broken ASG/proxy code (`supabase/supabase.tf`)

The previous `supabase.tf` contained broken ASG binding code that returned 403s
for typical Terraform service-account permissions. The working deployment does
not need it for RDS or S3 because cloud.gov app-to-backing-service connectivity
is handled by the platform.

If future services require outbound internet access, such as external OAuth
providers, SMTP relays, or Edge Functions user code, an egress proxy can be added
by the caller using the cloud.gov egress proxy module.

---

## First-Time Deployment

### Prerequisites

- Terraform >= 1.0
- cloud.gov credentials for one of the configured Terraform provider auth modes
- Access to the target cloud.gov org and space
- Access to GHCR-hosted scanned images used by the module

### Steps

```sh
# 1. Authenticate to cloud.gov if using an interactive auth mode.
cf login -a https://api.fr.cloud.gov --sso
cf target -o gsa-tts-oros-sorndashboard -s supabase

# 2. Configure Terraform auth.
cp vars.auto.tfvars-example vars.auto.tfvars
# Fill in one auth option block, or set the matching TF_VAR_* environment vars.

# 3. Deploy infrastructure and apps.
terraform init
terraform apply

# 4. Retrieve the generated Studio basic-auth password.
terraform output -raw dashboard_password
```

No separate JWT-generation or database-prep script is required. JWT material is
stored in Terraform state, and database schema initialization runs from pg-meta
startup using idempotent SQL.

### Subsequent Deploys

```sh
terraform apply
```

Generated JWT secrets and the dashboard password are stored in Terraform state.
On subsequent applies, Terraform reuses the same values unless state is replaced
or explicit input variables are changed.

---

## Architecture Overview

```text
Internet
    |
    v
Kong (supabase-supabase.app.cloud.gov)    <- public route
    |  CF network policies to 61443 for platform-managed app-to-app encryption
    |---> supabase-auth.apps.internal:61443     -> app:8080  <- GoTrue (auth)
    |---> supabase-rest.apps.internal:61443     -> app:8080  <- PostgREST (REST API)
    |---> supabase-storage.apps.internal:61443  -> app:8080  <- Storage API
    |---> supabase-meta.apps.internal:61443     -> app:8080  <- pg-meta (schema browser)
    `---> supabase-studio.apps.internal:61443   -> app:8080  <- Studio UI

Studio (SSR)
    |---> supabase-rest.apps.internal:61443     -> app:8080  <- direct for server-side rendering
    `---> supabase-meta.apps.internal:61443     -> app:8080  <- direct for schema browser

All apps
    `---> supabase-db (aws-rds)             <- RDS Postgres, per-app service keys

supabase-storage
    `---> supabase-private-s3 (s3)          <- S3 bucket for file storage
```

### Realtime

Realtime is not deployed. Cloud Foundry containers lack IPv6 kernel support, and
`supabase/realtime` hardcodes `socket_opts: [:inet6]` with no environment
variable override. The Kong routes for `/realtime/v1/*` are commented out.

---

## Known Limitations

| Issue | Status |
|---|---|
| Realtime disabled | By design; requires platform IPv6 support or a custom Realtime image |
| SMTP not configured | GoTrue uses `GOTRUE_MAILER_AUTOCONFIRM=true`; future SES support should accept a caller-provided cloud.gov SES service instance |
| Studio analytics | `NEXT_ANALYTICS_BACKEND_PROVIDER=bigquery` avoids unsupported direct Postgres analytics connections; Logflare/analytics is not deployed |
| Edge Functions | Not deployed; would need a feasibility investigation and likely egress-proxy support |
