locals {
  studio_image          = "ghcr.io/gsa-tts/cg-supabase/studio"
  studio_image_tag      = "scanned"
  studio_url            = "https://${cloudfoundry_route.supabase-studio.url}:61443"
  studio_db_credentials = jsondecode(cloudfoundry_service_credential_binding.studio.credential_binding).credentials
}

resource "cloudfoundry_route" "supabase-studio" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.private.id
  host   = "supabase-studio${local.slug}"
}

resource "cloudfoundry_service_credential_binding" "studio" {
  type             = "key"
  name             = "studio"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "studio" {
  name = "${local.studio_image}:${local.studio_image_tag}"
}

resource "cloudfoundry_app" "supabase-studio" {
  name         = local.studio_app_name
  org_name     = local.cf_org_name
  space_name   = local.cf_space_name
  docker_image = "${local.studio_image}@${data.docker_registry_image.studio.sha256_digest}"
  timeout      = 180
  memory       = var.studio_memory
  disk_quota   = "2048M"
  instances    = var.studio_instances
  strategy     = "none"

  health_check_type = "port"

  routes = [
    {
      route = cloudfoundry_route.supabase-studio.url
    }
  ]

  command = <<-CMD
    ${local.rds_ca_setup}
    exec /usr/local/bin/docker-entrypoint.sh node /app/apps/studio/server.js
  CMD

  environment = {
    # https://github.com/supabase/supabase/blob/master/apps/studio/.env

    HOSTNAME                  = "0.0.0.0"
    DEFAULT_ORGANIZATION_NAME = "Default Organization"
    DEFAULT_PROJECT_NAME      = "Default Project"

    # SUPABASE_URL: used by Studio server (SSR) — calls PostgREST directly via internal route.
    # SUPABASE_PUBLIC_URL: exposed to the browser — must be the public Kong API gateway URL.
    SUPABASE_URL        = local.rest_url
    SUPABASE_PUBLIC_URL = local.api_url
    STUDIO_PG_META_URL  = local.meta_url

    SUPABASE_ANON_KEY    = local.effective_anon_key
    SUPABASE_SERVICE_KEY = local.effective_service_role_key
    AUTH_JWT_SECRET      = local.effective_jwt_secret

    # Direct database connection for Studio's schema browser and SQL editor.
    # Studio builds a PostgreSQL URL from these vars via string interpolation and sends
    # it (AES-encrypted) to pg-meta in an x-connection-encrypted header. pg-meta opens
    # a per-request connection pool from the decrypted URL.
    #
    # SSL must be embedded in POSTGRES_DB as a query parameter — there is no
    # POSTGRES_SSLMODE env var and no other injection point on this code path.
    # Studio sends the encrypted connection string to pg-meta, which opens a
    # per-request pool. Certificate validation uses NODE_EXTRA_CA_CERTS from
    # the startup CA bootstrap on both Studio and pg-meta processes.
    #
    # All POSTGRES_* vars must be set: if POSTGRES_HOST is absent Studio falls back to
    # hostname "db" (Docker Compose default) and pg-meta returns ENOTFOUND.
    POSTGRES_HOST            = local.studio_db_credentials.host
    POSTGRES_PORT            = tostring(local.studio_db_credentials.port)
    POSTGRES_DB              = "${local.studio_db_credentials.db_name}?sslmode=require"
    POSTGRES_USER_READ_WRITE = local.studio_db_credentials.username
    POSTGRES_USER_READ_ONLY  = local.studio_db_credentials.username
    POSTGRES_PASSWORD        = local.studio_db_credentials.password

    NEXT_PUBLIC_ENABLE_LOGS = "true"
    # "postgres" causes Studio to make additional direct DB connections for analytics
    # (also without SSL), which fail against cloud.gov RDS. "bigquery" disables that path.
    NEXT_ANALYTICS_BACKEND_PROVIDER = "bigquery"
  }

  depends_on = [
    cloudfoundry_service_credential_binding.studio,
    cloudfoundry_service_credential_binding.s3,
  ]
}

# Studio needs to reach PostgREST directly (server-side API calls via SUPABASE_URL)
resource "cloudfoundry_network_policy" "studio-rest" {
  policies = [
    {
      source_app      = cloudfoundry_app.supabase-studio.id
      destination_app = cloudfoundry_app.supabase-rest.id
      port            = "61443"
    }
  ]
}

# Studio needs to reach pg-meta for the schema browser
resource "cloudfoundry_network_policy" "studio-meta" {
  policies = [
    {
      source_app      = cloudfoundry_app.supabase-studio.id
      destination_app = cloudfoundry_app.supabase-meta.id
      port            = "61443"
    }
  ]
}
