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

  # ---------------------------------------------------------------------------
  # Database schema init SQL — idempotent DDL executed by pg-meta at startup.
  # Creates extensions, roles, schemas, and migration-tracking tables that
  # GoTrue and Storage expect before their first run.  See also:
  # scripts/db_schema_init.sql (documentation copy).
  # ---------------------------------------------------------------------------
  db_schema_init_sql = <<-SQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS citext;

    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin NOLOGIN;
      END IF;
    END
    $$;

    DO $$
    DECLARE
      app_user text := current_user;
    BEGIN
      EXECUTE format('GRANT anon TO %I', app_user);
      EXECUTE format('GRANT authenticated TO %I', app_user);
      EXECUTE format('GRANT service_role TO %I', app_user);
      EXECUTE format('GRANT supabase_admin TO %I', app_user);
    END
    $$;

    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS storage;
    CREATE SCHEMA IF NOT EXISTS _realtime;
    CREATE SCHEMA IF NOT EXISTS extensions;

    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

    GRANT USAGE ON SCHEMA auth TO service_role;

    GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
    GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

    SET search_path TO auth;
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(14) NOT NULL,
      PRIMARY KEY (version)
    );
    CREATE UNIQUE INDEX IF NOT EXISTS schema_migrations_version_idx ON schema_migrations (version);
    RESET search_path;

    SET search_path TO _realtime;
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version  BIGINT NOT NULL,
      inserted_at TIMESTAMP(0) DEFAULT NOW(),
      PRIMARY KEY (version)
    );
    RESET search_path;

    SELECT 'DB schema init complete.' AS status;
  SQL

  # ---------------------------------------------------------------------------
  # RDS CA bootstrap — inline shell snippet sourced by each Node.js service's
  # startup command.  Builds a combined CA bundle (CF platform certs + AWS
  # GovCloud RDS CA) and exports NODE_EXTRA_CA_CERTS so that node-postgres
  # validates the RDS certificate chain instead of disabling TLS verification.
  # ---------------------------------------------------------------------------
  rds_ca_url = "https://truststore.pki.us-gov-west-1.rds.amazonaws.com/us-gov-west-1/us-gov-west-1-bundle.pem"
  rds_ca_setup = <<-SH
    CA_BUNDLE="/tmp/combined-ca-bundle.pem"
    cat /etc/cf-system-certificates/*.crt > "$CA_BUNDLE" 2>/dev/null || true
    node -e "const h=require('https'),f=require('fs');h.get('${local.rds_ca_url}',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>f.appendFileSync('$CA_BUNDLE',d))}).on('error',e=>{console.error('RDS CA fetch failed:',e.message);process.exit(1)})"
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
