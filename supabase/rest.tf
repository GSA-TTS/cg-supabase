locals {
  rest_image  = "ghcr.io/gsa-tts/cg-supabase/rest"
  rest_image_tag = "scanned"
  rest_url    = "https://${cloudfoundry_route.supabase-rest.endpoint}:61443"
  # PostgREST is a Go service — sslmode=prefer encrypts without requiring cert validation
  rest_connection_string = "${cloudfoundry_service_key.rest.credentials.uri}?sslmode=prefer"
}

resource "cloudfoundry_route" "supabase-rest" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-rest${local.slug}"
}

resource "cloudfoundry_service_key" "rest" {
  name             = "rest"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "rest" {
  name = "${local.rest_image}:${local.rest_image_tag}"
}

resource "cloudfoundry_app" "supabase-rest" {
  name         = local.rest_app_name
  space        = data.cloudfoundry_space.apps.id
  docker_image = "${local.rest_image}@${data.docker_registry_image.rest.sha256_digest}"
  timeout      = 600
  memory       = var.rest_memory
  disk_quota   = 256
  instances    = var.rest_instances
  strategy     = "rolling"

  health_check_type = "port"

  routes {
    route = cloudfoundry_route.supabase-rest.id
  }

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
    cloudfoundry_service_key.rest,
    cloudfoundry_app.supabase-meta, # schema init creates roles for SET ROLE
  ]
}
