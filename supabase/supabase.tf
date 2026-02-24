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
  effective_jwt_secret      = var.jwt_secret != "" ? var.jwt_secret : random_password.jwt_secret.result
  effective_anon_key        = var.anon_key != "" ? var.anon_key : data.external.anon_jwt.result["jwt"]
  effective_service_role_key = var.service_role_key != "" ? var.service_role_key : data.external.service_role_jwt.result["jwt"]
}

# ---------------------------------------------------------------------------
# Auto-generated JWT secret (used when var.jwt_secret is not provided)
# ---------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 40
  special = false
}

data "external" "anon_jwt" {
  program = ["python3", "${path.module}/../scripts/generate_jwt.py"]
  query = {
    secret = local.effective_jwt_secret
    role   = "anon"
  }
}

data "external" "service_role_jwt" {
  program = ["python3", "${path.module}/../scripts/generate_jwt.py"]
  query = {
    secret = local.effective_jwt_secret
    role   = "service_role"
  }
}

# ---------------------------------------------------------------------------
# Core infrastructure
# ---------------------------------------------------------------------------

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
