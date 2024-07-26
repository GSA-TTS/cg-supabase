locals {
  # TODO: Parameterize which image to use, with this as the default
  # TODO: Once Supabase publishes an image without CRITICAL and HIGH findings,
  #    switch to ghcr.io/gsa-tts/cg-supabase/studio:scanned
  studio_image             = "ghcr.io/supabase/studio"
  studio_image_tag         = "v1.24.05"
  studio_url               = "https://${cloudfoundry_route.supabase-studio.endpoint}"
  studio_connection_string = "${cloudfoundry_service_key.studio.credentials.uri}?sslmode=require"

}

resource "cloudfoundry_route" "supabase-studio" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-studio${local.slug}"
  port     = 3000
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
  routes {
    route = cloudfoundry_route.supabase-studio.id
  }
  health_check_type          = "http"
  health_check_http_endpoint = "/api/profile"

  command = <<-EOT
    # Make sure the Cloud Foundry-provided CA is recognized when making TLS connections
    cat /etc/cf-system-certificates/* > /usr/local/share/ca-certificates/cf-system-certificates.crt
    /usr/sbin/update-ca-certificates
    # Now call the expected ENTRYPOINT and CMD
    /usr/local/bin/docker-entrypoint.sh node /app/apps/studio/server.js
    EOT
  environment = {
    # Upstream docs: https://github.com/supabase/supabase/blob/master/apps/studio/.env

    # TODO: Move the secrets into a bound UPSI, and parse them out of
    # VCAP_SERVICES with jq at startup

    PGRST_DB_URI : local.rest_connection_string
    POSTGRES_PASSWORD : cloudfoundry_service_key.storage.credentials.password
    PGRST_JWT_SECRET : var.jwt_secret

    PGRST_DB_SCHEMAS : "public,storage,graphql_public"
    PGRST_DB_ANON_ROLE : "anon"
    PGRST_DB_MAX_ROWS : 20000

    STUDIO_PG_META_URL : local.meta_url

    DEFAULT_ORGANIZATION_NAME : "Default Organization"
    DEFAULT_PROJECT_NAME : "Default Project"

    SUPABASE_URL : local.studio_url
    SUPABASE_PUBLIC_URL : local.studio_url
    SUPABASE_ANON_KEY : var.anon_key
    SUPABASE_SERVICE_KEY : var.service_role_key

    LOGFLARE_API_KEY : var.logflare_api_key
    LOGFLARE_URL : "http://analytics:4000"
    NEXT_PUBLIC_ENABLE_LOGS : "true"
    NEXT_ANALYTICS_BACKEND_PROVIDER : "postgres"
  }
}
