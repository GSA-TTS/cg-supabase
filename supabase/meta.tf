locals {
  # TODO: Parameterize which image to use, with this as the default
  # TODO: Once Supabase publishes an image without CRITICAL and HIGH findings,
  #    switch to ghcr.io/gsa-tts/cg-supabase/postgres-meta:scanned
  meta_image             = "ghcr.io/supabase/postgres-meta"
  meta_image_tag         = "v0.81.2"
  meta_url               = "https://${cloudfoundry_route.supabase-meta.endpoint}:61443"
  meta_connection_string = "${cloudfoundry_service_key.meta.credentials.uri}?sslmode=require"
}

resource "cloudfoundry_route" "supabase-meta" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-meta${local.slug}"
}

resource "cloudfoundry_service_key" "meta" {
  name             = "meta"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "meta" {
  name = "${local.meta_image}:${local.meta_image_tag}"
}

resource "cloudfoundry_app" "supabase-meta" {
  name         = local.meta_app_name
  space        = data.cloudfoundry_space.apps.id
  docker_image = "${local.meta_image}@${data.docker_registry_image.meta.sha256_digest}"
  timeout      = 180
  memory       = var.meta_memory
  disk_quota   = 1024
  instances    = var.meta_instances
  strategy     = "rolling"
  routes {
    route = cloudfoundry_route.supabase-meta.id
  }
  health_check_type          = "http"
  health_check_http_endpoint = "/"
  
  command = <<-EOT
    # Make sure the Cloud Foundry-provided CA is recognized when making TLS connections
    cat /etc/cf-system-certificates/* > /usr/local/share/ca-certificates/cf-system-certificates.crt
    /usr/sbin/update-ca-certificates
    # Now call the expected ENTRYPOINT and CMD
    cd /usr/src/app && /usr/local/bin/docker-entrypoint.sh node dist/server/server.js
    EOT
  environment = {
    # Upstream docs: https://github.com/supabase/postgres-meta/blob/master/README.md#quickstart

    # TODO: Move the secrets into a bound UPSI, and parse them out of
    # VCAP_SERVICES with jq at startup
    PG_META_DB_URL = local.meta_connection_string
    PG_META_HOST   = "0.0.0.0"
    PG_META_PORT   = 8080
  }
}
