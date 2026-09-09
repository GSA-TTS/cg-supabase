locals {
  rest_image          = "ghcr.io/gsa-tts/cg-supabase/rest"
  rest_image_tag      = "scanned"
  rest_url            = "http://supabase-rest${local.slug}.apps.internal:3000"
  rest_db_credentials = jsondecode(cloudfoundry_service_credential_binding.rest.credential_binding).credentials
  # PostgREST is a Go service — sslmode=prefer encrypts without requiring cert validation
  rest_connection_string = "${local.rest_db_credentials.uri}?sslmode=prefer"
}

resource "cloudfoundry_route" "supabase-rest" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.private.id
  host   = "supabase-rest${local.slug}"
  destinations = [
    {
      app_id = cloudfoundry_app.supabase-rest.id
      port   = 3000
    }
  ]
}

resource "cloudfoundry_service_credential_binding" "rest" {
  type             = "key"
  name             = "rest"
  service_instance = local.database_service_instance_id
}

data "docker_registry_image" "rest" {
  name = "${local.rest_image}:${local.rest_image_tag}"
}

resource "cloudfoundry_app" "supabase-rest" {
  name         = local.rest_app_name
  org_name     = local.cf_org_name
  space_name   = local.cf_space_name
  docker_image = "${local.rest_image}@${data.docker_registry_image.rest.sha256_digest}"
  timeout      = 180
  memory       = var.rest_memory
  disk_quota   = "256M"
  instances    = var.rest_instances
  strategy     = "none"

  health_check_type = "port"

  environment = {
    # https://postgrest.org/en/v12/references/configuration.html
    PGRST_DB_URI             = local.rest_connection_string
    PGRST_DB_SCHEMAS         = "public,storage,graphql_public"
    PGRST_DB_ANON_ROLE       = "anon"
    PGRST_DB_USE_LEGACY_GUCS = "false"
    PGRST_DB_MAX_ROWS        = "20000"
    PGRST_JWT_SECRET         = local.effective_jwt_secret
    PGRST_SERVER_PORT        = "3000"
  }

  depends_on = [
    cloudfoundry_service_credential_binding.rest,
    cloudfoundry_app.supabase-meta, # schema init creates roles for SET ROLE
  ]
}
