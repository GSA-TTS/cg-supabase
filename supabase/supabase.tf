locals {
  # Names to use for each app (matches upstream docker-compose.yml)
  api_app_name     = "supabase-api"
  meta_app_name    = "supabase-meta"
  rest_app_name    = "supabase-rest"
  storage_app_name = "supabase-storage"
  studio_app_name  = "supabase-studio"

  cf_org_name   = data.cloudfoundry_org.apps.name
  cf_space_name = data.cloudfoundry_space.apps.name

  # A generated slug for use in domain names to avoid collisions, etc.
  slug = "-${trim(replace(replace(lower(var.cf_space_name), "/[^\\w_]/", "-"), "/-+/", "-"), "-")}"

  # ---------------------------------------------------------------------------
  # Effective secrets: use provided vars when non-empty, otherwise auto-generate.
  # jwt_secret drives anon_key and service_role_key; all three can be overridden.
  # ---------------------------------------------------------------------------
  effective_jwt_secret       = var.jwt_secret != "" ? var.jwt_secret : random_password.jwt_secret.result
  effective_anon_key         = var.anon_key != "" ? var.anon_key : jwt_hashed_token.anon.token
  effective_service_role_key = var.service_role_key != "" ? var.service_role_key : jwt_hashed_token.service_role.token

  # ---------------------------------------------------------------------------
  # Database schema init SQL — idempotent DDL executed by pg-meta at startup.
  # Creates extensions, roles, schemas, and migration-tracking tables that
  # GoTrue and Storage expect before their first run.
  # ---------------------------------------------------------------------------
  db_schema_init_sql = file("${path.module}/../scripts/db_schema_init.sql")

  # ---------------------------------------------------------------------------
  # RDS CA bootstrap — inline shell snippet sourced by each Node.js service's
  # startup command. Builds a combined CA bundle (CF platform certs + AWS
  # GovCloud RDS CA) and exports NODE_EXTRA_CA_CERTS so that node-postgres
  # validates the RDS certificate chain instead of disabling TLS verification.
  # The AWS bundle is loaded from the module, avoiding runtime egress dependency.
  # ---------------------------------------------------------------------------
  rds_ca_bundle_pem = file("${path.module}/us-gov-west-1-rds-ca-bundle.pem")
  rds_ca_setup      = <<-SH
    CA_BUNDLE="/tmp/combined-ca-bundle.pem"
    cat /etc/cf-system-certificates/*.crt > "$CA_BUNDLE" 2>/dev/null || true
    cat >> "$CA_BUNDLE" <<'RDS_CA_BUNDLE'
${local.rds_ca_bundle_pem}
RDS_CA_BUNDLE
    export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
  SH
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

# The beating heart of all Supabase services is a Postgres database
module "database" {
  source        = "github.com/GSA-TTS/terraform-cloudgov//database?ref=v2.0.0"
  cf_space_id   = data.cloudfoundry_space.apps.id
  name          = "supabase-db"
  rds_plan_name = var.database_plan
}

data "cloudfoundry_org" "apps" {
  name = var.cf_org_name
}

data "cloudfoundry_space" "apps" {
  org  = data.cloudfoundry_org.apps.id
  name = var.cf_space_name
}

data "cloudfoundry_domain" "public" {
  name = "app.cloud.gov"
}

data "cloudfoundry_domain" "private" {
  name = "apps.internal"
}
