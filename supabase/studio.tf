locals {
  studio_image     = "ghcr.io/gsa-tts/cg-supabase/studio"
  studio_image_tag = "scanned"
  studio_url       = "https://${cloudfoundry_route.supabase-studio.endpoint}:61443"
}

resource "cloudfoundry_route" "supabase-studio" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-studio${local.slug}"
}

resource "cloudfoundry_service_key" "studio" {
  name             = "studio"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "studio" {
  name = "${local.studio_image}:${local.studio_image_tag}"
}

resource "cloudfoundry_app" "supabase-studio" {
  name         = local.studio_app_name
  space        = data.cloudfoundry_space.apps.id
  docker_image = "${local.studio_image}@${data.docker_registry_image.studio.sha256_digest}"
  timeout      = 180
  memory       = var.studio_memory
  disk_quota   = 1024
  instances    = var.studio_instances
  strategy     = "rolling"

  health_check_type              = "http"
  health_check_http_endpoint     = "/api/profile"
  health_check_invocation_timeout = 30

  routes {
    route = cloudfoundry_route.supabase-studio.id
  }

  command = <<-EOT
    # Trust the Cloud Foundry-provided CA for TLS connections to internal services
    cat /etc/cf-system-certificates/* > /usr/local/share/ca-certificates/cf-system-certificates.crt
    /usr/sbin/update-ca-certificates
    /usr/local/bin/docker-entrypoint.sh node /app/apps/studio/server.js
    EOT

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
    # sslmode=no-verify → pg-meta sets ssl: { rejectUnauthorized: false },
    # which cloud.gov RDS accepts (SSL is still used; only cert-chain validation is skipped).
    #
    # All POSTGRES_* vars must be set: if POSTGRES_HOST is absent Studio falls back to
    # hostname "db" (Docker Compose default) and pg-meta returns ENOTFOUND.
    POSTGRES_HOST            = cloudfoundry_service_key.studio.credentials.host
    POSTGRES_PORT            = tostring(cloudfoundry_service_key.studio.credentials.port)
    POSTGRES_DB              = "${cloudfoundry_service_key.studio.credentials.db_name}?sslmode=no-verify"
    POSTGRES_USER_READ_WRITE = cloudfoundry_service_key.studio.credentials.username
    POSTGRES_USER_READ_ONLY  = cloudfoundry_service_key.studio.credentials.username
    POSTGRES_PASSWORD        = cloudfoundry_service_key.studio.credentials.password

    # NODE_TLS_REJECT_UNAUTHORIZED disables cert-chain validation for all other Node.js
    # DB connections in Studio. PGSSLMODE is not read by node-postgres and has no effect.
    NODE_TLS_REJECT_UNAUTHORIZED = "0"

    NEXT_PUBLIC_ENABLE_LOGS         = "true"
    # "postgres" causes Studio to make additional direct DB connections for analytics
    # (also without SSL), which fail against cloud.gov RDS. "bigquery" disables that path.
    NEXT_ANALYTICS_BACKEND_PROVIDER = "bigquery"
  }

  depends_on = [
    cloudfoundry_service_key.studio,
    cloudfoundry_service_key.s3,
  ]
}

# Studio needs to reach PostgREST directly (server-side API calls via SUPABASE_URL)
resource "cloudfoundry_network_policy" "studio-rest" {
  policy {
    source_app      = cloudfoundry_app.supabase-studio.id
    destination_app = cloudfoundry_app.supabase-rest.id
    port            = "61443"
  }
}

# Studio needs to reach pg-meta for the schema browser
resource "cloudfoundry_network_policy" "studio-meta" {
  policy {
    source_app      = cloudfoundry_app.supabase-studio.id
    destination_app = cloudfoundry_app.supabase-meta.id
    port            = "61443"
  }
}
