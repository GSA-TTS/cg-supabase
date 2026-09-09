locals {
  storage_image          = "ghcr.io/gsa-tts/cg-supabase/storage"
  storage_image_tag      = "scanned"
  storage_url            = "http://supabase-storage${local.slug}.apps.internal:5000"
  storage_db_credentials = jsondecode(cloudfoundry_service_credential_binding.storage.credential_binding).credentials
  s3_credentials         = jsondecode(cloudfoundry_service_credential_binding.s3.credential_binding).credentials
  # storage is a Node.js service; RDS CA validation is configured via NODE_EXTRA_CA_CERTS.
  storage_connection_string = "${local.storage_db_credentials.uri}?sslmode=prefer"
}

resource "cloudfoundry_route" "supabase-storage" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.private.id
  host   = "supabase-storage${local.slug}"
  destinations = [
    {
      app_id = cloudfoundry_app.supabase-storage.id
      port   = 5000
    }
  ]
}

resource "cloudfoundry_service_credential_binding" "storage" {
  type             = "key"
  name             = "storage"
  service_instance = local.database_service_instance_id
}

# Storage needs an S3 bucket to manage.
# Smoke tests can pre-create backing services with the CF CLI to avoid a
# cloudfoundry provider v1.18.0 crash when managed services omit maintenance_info.
module "s3-private" {
  count = var.s3_service_instance_name == "" ? 1 : 0

  source = "github.com/GSA-TTS/terraform-cloudgov//s3?ref=v2.0.0"

  cf_space_id  = data.cloudfoundry_space.apps.id
  name         = "supabase-private-s3"
  s3_plan_name = var.s3_plan_name
}

data "cloudfoundry_service_instance" "s3" {
  count = var.s3_service_instance_name == "" ? 0 : 1

  name  = var.s3_service_instance_name
  space = data.cloudfoundry_space.apps.id
}

resource "cloudfoundry_service_credential_binding" "s3" {
  type             = "key"
  name             = "storage"
  service_instance = local.s3_service_instance_id
}

data "docker_registry_image" "storage" {
  name = "${local.storage_image}:${local.storage_image_tag}"
}

resource "cloudfoundry_app" "supabase-storage" {
  name         = local.storage_app_name
  org_name     = local.cf_org_name
  space_name   = local.cf_space_name
  docker_image = "${local.storage_image}@${data.docker_registry_image.storage.sha256_digest}"
  timeout      = 180
  memory       = var.storage_memory
  disk_quota   = "1024M"
  instances    = var.storage_instances
  strategy     = "none"

  health_check_type               = "http"
  health_check_http_endpoint      = "/status"
  health_check_invocation_timeout = 30

  command = <<-CMD
    ${local.rds_ca_setup}
    exec docker-entrypoint.sh node /app/dist/start/server.js
  CMD

  environment = {
    # https://github.com/supabase/storage

    # Auth
    ANON_KEY    = local.effective_anon_key
    SERVICE_KEY = local.effective_service_role_key

    # PostgREST integration (storage uses PostgREST for permission checks)
    POSTGREST_URL     = local.rest_url
    PGRST_JWT_SECRET  = local.effective_jwt_secret
    RDS_CA_BUNDLE_PEM = local.rds_ca_bundle_pem

    # Database — certificate validation uses NODE_EXTRA_CA_CERTS from the
    # startup CA bootstrap with the AWS GovCloud RDS CA bundle.
    DATABASE_URL             = local.storage_connection_string
    DATABASE_POOL_URL        = local.storage_connection_string
    DATABASE_MULTITENANT_URL = local.storage_connection_string
    DB_SEARCH_PATH           = "storage,public,extensions"
    DB_SUPER_USER            = local.storage_db_credentials.username
    AUTH_JWT_SECRET          = local.effective_jwt_secret
    AUTH_JWT_ALGORITHM       = "HS256"
    # Shared roles are created idempotently by scripts/db_schema_init.sql.
    DB_INSTALL_ROLES = "false"

    # S3 backend (cloud.gov s3 broker — FIPS endpoint for GovCloud compliance)
    STORAGE_BACKEND             = "s3"
    STORAGE_S3_BUCKET           = local.s3_credentials.bucket
    STORAGE_S3_ENDPOINT         = local.s3_credentials.fips_endpoint
    STORAGE_S3_REGION           = local.s3_credentials.region
    STORAGE_S3_FORCE_PATH_STYLE = "true"
    STORAGE_S3_MAX_SOCKETS      = "200"
    # Legacy env vars (older storage-api versions read GLOBAL_S3_* instead of STORAGE_S3_*)
    GLOBAL_S3_BUCKET           = local.s3_credentials.bucket
    GLOBAL_S3_ENDPOINT         = "https://s3.${local.s3_credentials.region}.amazonaws.com"
    GLOBAL_S3_REGION           = local.s3_credentials.region
    GLOBAL_S3_FORCE_PATH_STYLE = "true"
    GLOBAL_S3_PROTOCOL         = "https"
    AWS_ACCESS_KEY_ID          = local.s3_credentials.access_key_id
    AWS_SECRET_ACCESS_KEY      = local.s3_credentials.secret_access_key
    AWS_DEFAULT_REGION         = local.s3_credentials.region
    REGION                     = local.s3_credentials.region

    # Tenant config (single-tenant mode)
    TENANT_ID                 = "default-tenant"
    IS_MULTITENANT            = "false"
    FILE_STORAGE_BACKEND_PATH = "/tmp/storage"
    FILE_SIZE_LIMIT           = "52428800"
  }

  depends_on = [
    cloudfoundry_service_credential_binding.storage,
    cloudfoundry_service_credential_binding.s3,
    cloudfoundry_app.supabase-meta, # schema init creates storage schema
  ]
}
