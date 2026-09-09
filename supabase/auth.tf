locals {
  auth_image          = "ghcr.io/gsa-tts/cg-supabase/auth"
  auth_image_tag      = "scanned"
  auth_app_name       = "supabase-auth"
  auth_url            = "http://supabase-auth${local.slug}.apps.internal:8080"
  auth_db_credentials = jsondecode(cloudfoundry_service_credential_binding.auth.credential_binding).credentials
  # GoTrue is a Go service — sslmode=prefer encrypts without requiring cert validation
  auth_connection_string = "${local.auth_db_credentials.uri}?search_path=auth&sslmode=prefer"
}

resource "cloudfoundry_route" "supabase-auth" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.private.id
  host   = "supabase-auth${local.slug}"
  destinations = [
    {
      app_id = cloudfoundry_app.supabase-auth.id
      port   = 8080
    }
  ]
}

resource "cloudfoundry_service_credential_binding" "auth" {
  type             = "key"
  name             = "auth"
  service_instance = local.database_service_instance_id
}

data "docker_registry_image" "auth" {
  name = "${local.auth_image}:${local.auth_image_tag}"
}

resource "cloudfoundry_app" "supabase-auth" {
  name         = local.auth_app_name
  org_name     = local.cf_org_name
  space_name   = local.cf_space_name
  docker_image = "${local.auth_image}@${data.docker_registry_image.auth.sha256_digest}"
  timeout      = 180
  memory       = var.auth_memory
  disk_quota   = "256M"
  instances    = var.auth_instances
  strategy     = "none"

  health_check_type               = "http"
  health_check_http_endpoint      = "/health"
  health_check_invocation_timeout = 30

  environment = {
    GOTRUE_API_HOST = "0.0.0.0"
    GOTRUE_API_PORT = "8080"

    # The public-facing URL for auth redirects (e.g. OAuth callbacks, email links)
    API_EXTERNAL_URL = local.api_url

    GOTRUE_DB_DRIVER       = "postgres"
    GOTRUE_DB_DATABASE_URL = local.auth_connection_string

    # Studio is reached via Kong; use the API gateway URL
    GOTRUE_SITE_URL       = local.api_url
    GOTRUE_URI_ALLOW_LIST = ""
    GOTRUE_DISABLE_SIGNUP = "false"

    GOTRUE_JWT_ADMIN_ROLES        = "service_role"
    GOTRUE_JWT_AUD                = "authenticated"
    GOTRUE_JWT_DEFAULT_GROUP_NAME = "authenticated"
    GOTRUE_JWT_EXP                = "3600"
    GOTRUE_JWT_SECRET             = local.effective_jwt_secret

    GOTRUE_EXTERNAL_EMAIL_ENABLED = "true"
    GOTRUE_MAILER_AUTOCONFIRM     = "true"
    GOTRUE_EXTERNAL_PHONE_ENABLED = "false"
    GOTRUE_SMS_AUTOCONFIRM        = "false"
  }

  depends_on = [
    cloudfoundry_service_credential_binding.auth,
    cloudfoundry_app.supabase-meta, # schema init creates auth schema + migration table
  ]
}
