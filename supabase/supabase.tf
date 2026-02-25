locals {
  # Names to use for each app (matches upstream docker-compose.yml)
  api_app_name     = "supabase-api"
  meta_app_name    = "supabase-meta"
  rest_app_name    = "supabase-rest"
  storage_app_name = "supabase-storage"
  studio_app_name  = "supabase-studio"

  # A generated slug for use in domain names to avoid collisions, etc.
  slug = "-${trim(replace(replace(lower(var.cf_space_name), "/[^\\w_]/", "-"), "/-+/", "-"), "-")}"

  # ---------------------------------------------------------------------------
  # Effective secrets: use provided vars when non-empty, otherwise auto-generate.
  # jwt_secret drives anon_key and service_role_key; all three can be overridden.
  # ---------------------------------------------------------------------------
  effective_jwt_secret       = var.jwt_secret != "" ? var.jwt_secret : random_password.jwt_secret.result
  effective_anon_key         = var.anon_key != "" ? var.anon_key : jwt_hashed_token.anon.token
  effective_service_role_key = var.service_role_key != "" ? var.service_role_key : jwt_hashed_token.service_role.token
}

# ---------------------------------------------------------------------------
# Auto-generated JWT secret (used when var.jwt_secret is not provided)
# ---------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 40
  special = false
}

# ---------------------------------------------------------------------------
# Auto-generated anon and service_role JWTs via camptocamp/jwt provider.
# iat/exp are fixed far-future timestamps (same convention as Supabase's
# official docker-compose demo). All three can be overridden via vars.
# ---------------------------------------------------------------------------
resource "jwt_hashed_token" "anon" {
  secret    = local.effective_jwt_secret
  algorithm = "HS256"
  claims_json = jsonencode({
    role = "anon"
    iss  = "supabase"
    iat  = 1741222400 # ~March 2025
    exp  = 1956778800 # ~December 2031
  })
}

resource "jwt_hashed_token" "service_role" {
  secret    = local.effective_jwt_secret
  algorithm = "HS256"
  claims_json = jsonencode({
    role = "service_role"
    iss  = "supabase"
    iat  = 1741222400 # ~March 2025
    exp  = 1956778800 # ~December 2031
  })
}

# ---------------------------------------------------------------------------
# Core infrastructure
# ---------------------------------------------------------------------------

# First-time database schema initialisation — runs once per new DB instance.
# Requires: psql in PATH and network access to the cloud.gov RDS endpoint.
# The SQL file creates the roles, schemas, and migration-tracking tables that
# GoTrue and Storage expect before their first startup.
resource "null_resource" "db_schema_init" {
  triggers = {
    # Re-run only when the database instance is replaced
    db_instance_id = module.database.instance_id
    service_key_id = cloudfoundry_service_key.meta.id
  }

  provisioner "local-exec" {
    environment = {
      PGPASSWORD = cloudfoundry_service_key.meta.credentials.password
      PGSSLMODE  = "require"
    }
    command = <<-CMD
      psql \
        -h "${cloudfoundry_service_key.meta.credentials.host}" \
        -p "${cloudfoundry_service_key.meta.credentials.port}" \
        -U "${cloudfoundry_service_key.meta.credentials.username}" \
        -d "${cloudfoundry_service_key.meta.credentials.db_name}" \
        -f "${path.module}/../scripts/db_schema_init.sql"
    CMD
  }

  depends_on = [module.database, cloudfoundry_service_key.meta]
}

# The beating heart of all Supabase services is a Postgres database
module "database" {
  source        = "github.com/GSA-TTS/terraform-cloudgov//database?ref=v2.0.0"
  cf_org_name   = var.cf_org_name
  cf_space_name = var.cf_space_name
  name          = "supabase-db"
  rds_plan_name = var.database_plan
}

data "cloudfoundry_space" "apps" {
  org_name = var.cf_org_name
  name     = var.cf_space_name
}

data "cloudfoundry_domain" "public" {
  name = "app.cloud.gov"
}

data "cloudfoundry_domain" "private" {
  name = "apps.internal"
}
