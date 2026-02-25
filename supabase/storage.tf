locals {
  storage_image     = "ghcr.io/gsa-tts/cg-supabase/storage"
  storage_image_tag = "scanned"
  storage_url       = "https://${cloudfoundry_route.supabase-storage.endpoint}:61443"
  # storage is a Node.js service — SSL mode set via PGSSLMODE + NODE_TLS_REJECT_UNAUTHORIZED
  storage_connection_string = "${cloudfoundry_service_key.storage.credentials.uri}?sslmode=prefer"
}

resource "cloudfoundry_route" "supabase-storage" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-storage${local.slug}"
}

resource "cloudfoundry_service_key" "storage" {
  name             = "storage"
  service_instance = module.database.instance_id
}

# Storage needs an S3 bucket to manage
module "s3-private" {
  source = "github.com/GSA-TTS/terraform-cloudgov//s3?ref=v2.0.0"

  cf_space_id  = data.cloudfoundry_space.apps.id
  name         = "supabase-private-s3"
  s3_plan_name = "basic"
}

resource "cloudfoundry_service_key" "s3" {
  name             = "storage"
  service_instance = module.s3-private.bucket_id
}

data "docker_registry_image" "storage" {
  name = "${local.storage_image}:${local.storage_image_tag}"
}

resource "cloudfoundry_app" "supabase-storage" {
  name         = local.storage_app_name
  space        = data.cloudfoundry_space.apps.id
  docker_image = "${local.storage_image}@${data.docker_registry_image.storage.sha256_digest}"
  timeout      = 180
  memory       = var.storage_memory
  disk_quota   = 1024
  instances    = var.storage_instances
  strategy     = "rolling"

  health_check_type              = "http"
  health_check_http_endpoint     = "/status"
  health_check_invocation_timeout = 30

  command = <<-CMD
    ${local.rds_ca_setup}
    exec docker-entrypoint.sh node /app/dist/start/server.js
  CMD

  routes {
    route = cloudfoundry_route.supabase-storage.id
  }

  environment = {
    # https://github.com/supabase/storage

    # Auth
    ANON_KEY    = local.effective_anon_key
    SERVICE_KEY = local.effective_service_role_key

    # PostgREST integration (storage uses PostgREST for permission checks)
    POSTGREST_URL    = local.rest_url
    PGRST_JWT_SECRET = local.effective_jwt_secret

    # Database — certificate validation uses NODE_EXTRA_CA_CERTS (set by rds-ca.sh
    # at startup) with the AWS GovCloud RDS CA bundle.
    DATABASE_URL             = local.storage_connection_string
    DATABASE_POOL_URL        = local.storage_connection_string
    DATABASE_MULTITENANT_URL = local.storage_connection_string
    DB_SEARCH_PATH           = "storage,public,extensions"
    DB_SUPER_USER            = cloudfoundry_service_key.storage.credentials.username
    AUTH_JWT_SECRET          = local.effective_jwt_secret
    AUTH_JWT_ALGORITHM       = "HS256"
    DB_INSTALL_ROLES         = "true"

    # S3 backend (cloud.gov s3 broker — FIPS endpoint for GovCloud compliance)
    STORAGE_BACKEND             = "s3"
    STORAGE_S3_BUCKET           = cloudfoundry_service_key.s3.credentials.bucket
    STORAGE_S3_ENDPOINT         = cloudfoundry_service_key.s3.credentials.fips_endpoint
    STORAGE_S3_REGION           = cloudfoundry_service_key.s3.credentials.region
    STORAGE_S3_FORCE_PATH_STYLE = "true"
    STORAGE_S3_MAX_SOCKETS      = "200"
    # Legacy env vars (older storage-api versions read GLOBAL_S3_* instead of STORAGE_S3_*)
    GLOBAL_S3_BUCKET            = cloudfoundry_service_key.s3.credentials.bucket
    GLOBAL_S3_ENDPOINT          = "https://s3.${cloudfoundry_service_key.s3.credentials.region}.amazonaws.com"
    GLOBAL_S3_REGION            = cloudfoundry_service_key.s3.credentials.region
    GLOBAL_S3_FORCE_PATH_STYLE  = "true"
    GLOBAL_S3_PROTOCOL          = "https"
    AWS_ACCESS_KEY_ID           = cloudfoundry_service_key.s3.credentials.access_key_id
    AWS_SECRET_ACCESS_KEY       = cloudfoundry_service_key.s3.credentials.secret_access_key
    AWS_DEFAULT_REGION          = cloudfoundry_service_key.s3.credentials.region
    REGION                      = cloudfoundry_service_key.s3.credentials.region

    # Tenant config (single-tenant mode)
    TENANT_ID                 = "default-tenant"
    IS_MULTITENANT            = "false"
    FILE_STORAGE_BACKEND_PATH = "/tmp/storage"
    FILE_SIZE_LIMIT           = "52428800"
  }

  depends_on = [
    cloudfoundry_service_key.storage,
    cloudfoundry_service_key.s3,
    cloudfoundry_app.supabase-meta, # schema init creates storage schema
  ]
}
