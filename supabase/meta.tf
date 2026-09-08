locals {
  meta_image          = "ghcr.io/gsa-tts/cg-supabase/meta"
  meta_image_tag      = "scanned"
  meta_url            = "https://${cloudfoundry_route.supabase-meta.url}:61443"
  meta_db_credentials = jsondecode(cloudfoundry_service_credential_binding.meta.credential_binding).credentials
}

resource "cloudfoundry_route" "supabase-meta" {
  space  = data.cloudfoundry_space.apps.id
  domain = data.cloudfoundry_domain.private.id
  host   = "supabase-meta${local.slug}"
}

resource "cloudfoundry_service_credential_binding" "meta" {
  type             = "key"
  name             = "meta"
  service_instance = module.database.instance_id
}

data "docker_registry_image" "meta" {
  name = "${local.meta_image}:${local.meta_image_tag}"
}

resource "cloudfoundry_app" "supabase-meta" {
  name         = local.meta_app_name
  org_name     = local.cf_org_name
  space_name   = local.cf_space_name
  docker_image = "${local.meta_image}@${data.docker_registry_image.meta.sha256_digest}"
  timeout      = 180
  memory       = var.meta_memory
  disk_quota   = "1024M"
  instances    = var.meta_instances
  strategy     = "none"

  health_check_type               = "http"
  health_check_http_endpoint      = "/"
  health_check_invocation_timeout = 30

  routes = [
    {
      route = cloudfoundry_route.supabase-meta.url
    }
  ]

  command = <<-CMD
    ${local.rds_ca_setup}
    cd /usr/src/app && node -e "
      const{Client}=require('pg');
      const c=new Client({
        host:process.env.PG_META_DB_HOST,
        port:+process.env.PG_META_DB_PORT,
        database:process.env.PG_META_DB_NAME,
        user:process.env.PG_META_DB_USER,
        password:process.env.PG_META_DB_PASSWORD,
        ssl:true
      });
      c.connect()
        .then(()=>c.query(process.env.DB_INIT_SQL))
        .then(()=>{console.log('DB schema init OK');return c.end()})
        .catch(e=>{console.error('DB schema init FAILED:',e.message);process.exit(1)});
    "
    exec docker-entrypoint.sh node /usr/src/app/dist/server/server.js
  CMD

  environment = {
    # https://github.com/supabase/postgres-meta#quickstart
    PG_META_PORT        = "8080"
    PG_META_DB_HOST     = local.meta_db_credentials.host
    PG_META_DB_PORT     = tostring(local.meta_db_credentials.port)
    PG_META_DB_NAME     = local.meta_db_credentials.db_name
    PG_META_DB_USER     = local.meta_db_credentials.username
    PG_META_DB_PASSWORD = local.meta_db_credentials.password
    # cloud.gov RDS requires SSL. node-postgres (pg) does not read the libpq PGSSLMODE
    # env var — use pg-meta's own SSL env var instead (available since pg-meta v0.85+).
    # Certificate validation uses NODE_EXTRA_CA_CERTS from the startup CA bootstrap
    # with the AWS GovCloud RDS CA bundle.
    PG_META_DB_SSL_MODE = "require"

    # Idempotent DDL executed before the server starts — creates extensions,
    # roles, schemas, and migration-tracking tables needed by downstream services.
    DB_INIT_SQL = local.db_schema_init_sql
  }

  depends_on = [cloudfoundry_service_credential_binding.meta]
}
