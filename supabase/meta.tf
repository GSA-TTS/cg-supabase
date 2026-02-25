locals {
  meta_image     = "ghcr.io/gsa-tts/cg-supabase/meta"
  meta_image_tag = "scanned"
  meta_url       = "https://${cloudfoundry_route.supabase-meta.endpoint}:61443"
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

  health_check_type              = "http"
  health_check_http_endpoint     = "/"
  health_check_invocation_timeout = 30

  routes {
    route = cloudfoundry_route.supabase-meta.id
  }

  command = <<-CMD
    ${local.rds_ca_setup}
    exec docker-entrypoint.sh node /usr/src/app/dist/server/server.js
  CMD

  environment = {
    # https://github.com/supabase/postgres-meta#quickstart
    PG_META_PORT        = "8080"
    PG_META_DB_HOST     = cloudfoundry_service_key.meta.credentials.host
    PG_META_DB_PORT     = tostring(cloudfoundry_service_key.meta.credentials.port)
    PG_META_DB_NAME     = cloudfoundry_service_key.meta.credentials.db_name
    PG_META_DB_USER     = cloudfoundry_service_key.meta.credentials.username
    PG_META_DB_PASSWORD = cloudfoundry_service_key.meta.credentials.password
    # cloud.gov RDS requires SSL. node-postgres (pg) does not read the libpq PGSSLMODE
    # env var — use pg-meta's own SSL env var instead (available since pg-meta v0.85+).
    # Certificate validation uses NODE_EXTRA_CA_CERTS (set by rds-ca.sh at startup)
    # with the AWS GovCloud RDS CA bundle.
    PG_META_DB_SSL_MODE = "require"
  }

  depends_on = [cloudfoundry_service_key.meta]
}
