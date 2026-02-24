# PR: Port Working cloud.gov Deployment Approach

## Summary

This PR ports the Terraform patterns proven in a successful Supabase deployment
(`my-supabase-gcloud/cloudgov`) into this repository. It fixes several
non-functional configurations, enables the auth service, and aligns all service
environment variables with the working deployment.

---

## What Changed and Why

### 1. Auth service enabled (`supabase/auth.tf`)

The entire `cloudfoundry_app.supabase-auth` resource was commented out. This
PR uncomments and fully configures it based on the working deployment:

- Switches to the GSA-TTS scanned image (`ghcr.io/gsa-tts/cg-supabase/auth:scanned`)
- Sets `GOTRUE_DB_DATABASE_URL` with `search_path=auth&sslmode=prefer` (Go
  services use `sslmode=prefer`; it encrypts the connection without requiring
  cert chain validation against cloud.gov's self-signed intermediate CA)
- Sets `GOTRUE_SITE_URL` and `API_EXTERNAL_URL` to the Kong gateway public URL
- Configures JWT claims, signup/email defaults

### 2. Kong network policy for auth enabled (`supabase/api.tf`)

The `cloudfoundry_network_policy` rule allowing Kong → auth was commented out.
It is now enabled so Kong can route `/auth/v1/*` to the auth app.

Stale Docker Compose-style hostnames for realtime (`realtime-dev.supabase-realtime`),
edge functions (`http://functions:9000`), and analytics (`http://analytics:4000`)
are replaced with commented-out placeholders using proper CF internal URL patterns.
These services are not deployed in the Terraform module.

### 3. Auto-generated JWT secrets (`supabase/supabase.tf`, `supabase/variables.tf`)

Previously, `jwt_secret`, `anon_key`, and `service_role_key` were required inputs
with no defaults. They are now optional (default `""`). When omitted:

- `jwt_secret` is generated via `random_password` (40-char alphanumeric)
- `anon_key` and `service_role_key` are derived from `jwt_secret` using
  `scripts/generate_jwt.py` (pure Python stdlib, no pip dependencies) via
  Terraform's `data "external"` resource

When values are provided, they take precedence (backward compatible).

### 4. SSL/TLS handling corrected across all services

cloud.gov RDS uses a self-signed intermediate CA that Go and Node.js do not
trust by default. The working deployment uses two different approaches:

| Runtime | Approach |
|---------|----------|
| Go (GoTrue, PostgREST) | `sslmode=prefer` in DB URI — encrypts without cert validation |
| Node.js (meta, storage, studio) | `PGSSLMODE=require` + `NODE_TLS_REJECT_UNAUTHORIZED=0` |

Previous configs used `sslmode=require` for Go services (which also works, but
`sslmode=prefer` is what the working deployment uses) and were missing
`NODE_TLS_REJECT_UNAUTHORIZED=0` for Node.js services entirely, causing
connection failures.

### 5. Meta service (`supabase/meta.tf`)

- Switched to GSA-TTS scanned image (`ghcr.io/gsa-tts/cg-supabase/meta:scanned`)
  replacing the outdated upstream image at `v0.81.2`
- Changed from the single `PG_META_DB_URL` env var to individual
  `PG_META_DB_HOST/PORT/NAME/USER/PASSWORD` vars (required by newer pg-meta versions)
- Added `PGSSLMODE=require` and `NODE_TLS_REJECT_UNAUTHORIZED=0`
- Removed the custom startup command that tried to install CF CA certs via
  `update-ca-certificates` — `NODE_TLS_REJECT_UNAUTHORIZED=0` makes this unnecessary

### 6. Storage service (`supabase/storage.tf`)

- Removed the startup command that used `apk`/`curl` to download the AWS RDS
  CA certificate bundle. That approach required outbound internet access (egress)
  and failed silently if the space's egress policy blocked it. Replaced with
  `NODE_TLS_REJECT_UNAUTHORIZED=0`
- Added `DB_SEARCH_PATH=storage,public,extensions` (required by the storage service)
- Added `IS_MULTITENANT=false` and `FILE_STORAGE_BACKEND_PATH=/tmp/storage`
- Added `GLOBAL_S3_*` env vars alongside `STORAGE_S3_*` for compatibility with
  different storage-api versions
- Added `AWS_DEFAULT_REGION` which some S3 client code paths require
- All secrets now reference `local.effective_*` locals (auto-gen or provided)

### 7. Studio service (`supabase/studio.tf`)

- Fixed `SUPABASE_URL`: was incorrectly pointing to Studio's own URL (circular).
  Now set to `local.rest_url` (PostgREST internal route) for server-side rendering
- Added `SUPABASE_PUBLIC_URL` pointing to Kong's public URL for browser-side calls
- Fixed `POSTGRES_PASSWORD`: was using the storage service key's password. Now
  uses studio's own service key credentials
- Added all `POSTGRES_*` connection variables required for the schema browser
  and SQL editor (`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`,
  `POSTGRES_USER_READ_WRITE`, `POSTGRES_USER_READ_ONLY`, `POSTGRES_PASSWORD`)
- Added `PGSSLMODE=require` and `NODE_TLS_REJECT_UNAUTHORIZED=0`
- Added `NEXT_PUBLIC_ENABLE_LOGS` and `NEXT_ANALYTICS_BACKEND_PROVIDER`
- Added `cloudfoundry_network_policy.studio-rest` so Studio can reach PostgREST
  directly via the CF internal route (needed for SSR API calls)

### 8. Provider authentication options (`providers-managed.tf`, `variables.tf`)

Added support for three CF authentication methods (previously only username/password):

- **Option A — Service account** (`cf_client_id` + `cf_client_secret`):
  Recommended for CI/CD; requires creating a cloud.gov OAuth2 service account
- **Option B — SSO passcode** (`cf_sso_passcode`):
  For interactive use; get a passcode from `cf login --sso`
- **Option C — Username/password** (`cf_user` + `cf_password`):
  Legacy approach; still supported for backward compatibility

Added `hashicorp/random` to required providers (for JWT secret auto-generation).

### 9. New scripts (`scripts/`)

**`scripts/generate_jwt.py`** — Pure Python 3 JWT generator (HS256). Called by
Terraform's `data "external"` to generate `anon_key` and `service_role_key`
from the JWT secret. Uses only stdlib (no pip install required).

**`scripts/cloudgov_db_prep.sh`** — One-time Postgres schema setup that must
be run after the first `terraform apply`. Creates the roles, schemas, and
migration tables that GoTrue and Storage expect to find. See
[First-Time Deployment](#first-time-deployment) below.

### 10. Removed broken ASG/proxy code (`supabase/supabase.tf`)

The previous `supabase.tf` contained:

```hcl
data "cloudfoundry_asg" "trusted-local-networks" { ... }
# TODO: This doesn't seem to be working; it gets a 403 response
# resource "cloudfoundry_space_asgs" "asgs" { ... }
```

And `main.tf` had a commented-out reference to `module.https-proxy.https_proxy`.

**Proxy evaluation**: The working deployment runs without an egress proxy.
Cloud Foundry app-to-backing-service connectivity (RDS, S3) is handled by the
platform via VPC peering — outbound internet egress is not required for database
or S3 bucket access. The `cloudfoundry_space_asgs` resource was removed because:

1. The service account used for Terraform typically lacks `OrgManager` role
   required to bind ASGs at the space level
2. The working deployment does not need it

If future services require outbound internet access (e.g., external OAuth
providers, SMTP), an egress proxy can be added via the
`github.com/GSA-TTS/terraform-cloudgov//egress_proxy` module.

---

## First-Time Deployment

### Prerequisites

- Terraform >= 1.0
- Python 3 (for JWT generation via `scripts/generate_jwt.py`)
- `cf` CLI v8+ logged into cloud.gov
- `psql` in PATH
- `cf connect-to-service` CF CLI plugin:
  ```sh
  cf install-plugin -r CF-Community "connect-to-service"
  ```

### Steps

```sh
# 1. Authenticate to cloud.gov (choose one method)
cf login -a https://api.fr.cloud.gov --sso
cf target -o gsa-tts-oros-sorndashboard -s supabase

# 2. Configure Terraform auth — copy and edit vars.auto.tfvars-example
cp vars.auto.tfvars-example vars.auto.tfvars
# Fill in one of the auth option blocks

# 3. Deploy infrastructure
terraform init
terraform apply

# 4. One-time database schema preparation (apps will crash-loop until this runs)
./scripts/cloudgov_db_prep.sh

# 5. Restart apps so they pick up the prepared schema
cf restart supabase-auth
cf restart supabase-storage
```

### Subsequent Deploys

```sh
terraform apply
```

JWT secrets are stored in Terraform state. On the first apply they are
auto-generated; on subsequent applies the same values are reused.

---

## Architecture Overview

```
Internet
    │
    ▼
Kong (supabase-supabase.app.cloud.gov)    ← public route
    │  CF network policies (port 61443)
    ├──► supabase-auth.apps.internal       ← GoTrue (auth)
    ├──► supabase-rest.apps.internal       ← PostgREST (REST API)
    ├──► supabase-storage.apps.internal    ← Storage API
    ├──► supabase-meta.apps.internal       ← pg-meta (schema browser)
    └──► supabase-studio.apps.internal     ← Studio UI

Studio (SSR)
    ├──► supabase-rest.apps.internal       ← direct for server-side rendering
    └──► supabase-meta.apps.internal       ← direct for schema browser

All apps
    └──► supabase-db (aws-rds)             ← RDS Postgres (each app has its own service key)

supabase-storage
    └──► supabase-private-s3 (s3)          ← S3 bucket for file storage
```

### Realtime

Realtime is **not deployed**. Cloud Foundry containers lack IPv6 kernel support,
and `supabase/realtime` hardcodes `socket_opts: [:inet6]` with no environment
variable override. The Kong routes for `/realtime/v1/*` are commented out.

---

## Known Limitations

| Issue | Status |
|-------|--------|
| Realtime disabled (IPv6) | By design — requires platform IPv6 or custom image |
| No SMTP configured | GoTrue has `GOTRUE_MAILER_AUTOCONFIRM=true`; configure SMTP env vars in auth.tf to enable email |
| Studio analytics | `NEXT_ANALYTICS_BACKEND_PROVIDER=postgres` uses the main DB; no separate Logflare |
| Edge functions | Not deployed; Kong route is commented out |
