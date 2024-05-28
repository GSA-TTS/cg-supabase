locals {
  # TODO: Parameterize which image to use, with this as the default
  rest_image             = "ghcr.io/gsa-tts/cg-supabase/rest"
  rest_image_tag         = "scanned"
  rest_url               = "https://${cloudfoundry_route.supabase-rest.endpoint}"
  rest_connection_string = "${cloudfoundry_service_key.rest.credentials.uri}?sslmode=require"
}

resource "cloudfoundry_route" "supabase-rest" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.public.id
  hostname = "supabase${local.slug}"
  path     = "/rest/v1"
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
  timeout      = 180
  memory       = var.rest_memory
  disk_quota   = 256
  instances    = var.rest_instances
  strategy     = "rolling"
  routes {
    route = cloudfoundry_route.supabase-rest.id
  }

  environment = {
    # Upstream docs: https://postgrest.org/en/v12/references/configuration.html

    # TODO: Move the secrets into a bound UPSI, and parse them out of
    # VCAP_SERVICES with jq at startup
    PGRST_DB_URI : local.rest_connection_string
    PGRST_JWT_SECRET : var.jwt_secret

    PGRST_DB_SCHEMAS : "public,storage,graphql_public"
    PGRST_DB_ANON_ROLE : "anon"
    PGRST_DB_MAX_ROWS : 20000
  }
}
