locals {
  # TODO: Parameterize which image to use, with this as the default
  storage_image             = "ghcr.io/gsa-tts/cg-supabase/storage"
  storage_image_tag         = "scanned"
  storage_url               = "https://${cloudfoundry_route.supabase-storage.endpoint}:61443"
  storage_connection_string = "${cloudfoundry_service_key.storage.credentials.uri}?sslmode=require"
}

resource "cloudfoundry_route" "supabase-storage" {
  space    = data.cloudfoundry_space.apps.id
  domain   = data.cloudfoundry_domain.private.id
  hostname = "supabase-storage${local.slug}"
}


resource "cloudfoundry_service_key" "storage" {
  name             = "storage"
  service_instance = module.database.instance_id
}

# Storage needs an S3 bucket to manage
module "s3-private" {
  source = "github.com/GSA-TTS/terraform-cloudgov//s3?ref=v1.0.0"

  cf_org_name   = var.cf_org_name
  cf_space_name = var.cf_space_name
  name          = "supabase-private-s3"
  s3_plan_name  = "basic"
}

resource "cloudfoundry_service_key" "s3" {
  name             = "storage"
  service_instance = module.s3-private.bucket_id
}

data "docker_registry_image" "storage" {
  name = "${local.storage_image}:${local.storage_image_tag}"
}

resource "cloudfoundry_app" "supabase-storage" {
  name         = local.storage_app_name
  space        = data.cloudfoundry_space.apps.id
  docker_image = "${local.storage_image}@${data.docker_registry_image.storage.sha256_digest}"
  timeout      = 180
  memory       = var.storage_memory
  disk_quota   = 1024
  instances    = var.storage_instances
  strategy     = "rolling"
  routes {
    route = cloudfoundry_route.supabase-storage.id
  }
  health_check_type          = "http"
  health_check_http_endpoint = "/status"
  command                    = <<-EOT
    # We need the AWS CA cert bundle in place for RDS connections
    apk --no-cache add curl && rm -rf /var/cache/apk/*
    mkdir ~/.postgresql
    curl https://truststore.pki.us-gov-west-1.rds.amazonaws.com/us-gov-west-1/us-gov-west-1-bundle.pem > ~/.postgresql/root.crt
    # NODE_EXTRA_CA_CERTS=~/.postgresql/root.crt NODE_DEBUG=net,http,tls node dist/server.js
    NODE_EXTRA_CA_CERTS=~/.postgresql/root.crt node dist/server.js
    EOT

  environment = {
    # Upstream example: https://github.com/supabase/storage/blob/master/.env.sample

    # TODO: Move the secrets into a bound UPSI, and parse them out of
    # VCAP_SERVICES with jq at startup

    # required
    ANON_KEY : var.anon_key
    SERVICE_KEY : var.service_role_key
    POSTGREST_URL : local.rest_url
    PGRST_JWT_SECRET : var.jwt_secret
    DATABASE_URL : local.storage_connection_string
    DATABASE_POOL_URL : local.storage_connection_string
    DATABASE_MULTITENANT_URL : local.storage_connection_string

    DB_SUPER_USER : cloudfoundry_service_key.storage.credentials.username
    AUTH_JWT_SECRET : var.jwt_secret
    AUTH_JWT_ALGORITHM : "HS256"
    DB_INSTALL_ROLES : true
    TENANT_ID : "default-tenant"

    STORAGE_BACKEND : "s3"
    STORAGE_S3_BUCKET : cloudfoundry_service_key.s3.credentials.bucket
    STORAGE_S3_MAX_SOCKETS : 200
    STORAGE_S3_ENDPOINT : cloudfoundry_service_key.s3.credentials.fips_endpoint
    STORAGE_S3_FORCE_PATH_STYLE : true
    STORAGE_S3_REGION : cloudfoundry_service_key.s3.credentials.region

    AWS_ACCESS_KEY_ID : cloudfoundry_service_key.s3.credentials.access_key_id
    AWS_SECRET_ACCESS_KEY : cloudfoundry_service_key.s3.credentials.secret_access_key

    REGION : cloudfoundry_service_key.s3.credentials.region
    GLOBAL_S3_BUCKET : cloudfoundry_service_key.s3.credentials.bucket
    PG_OPTIONS : ""
    FILE_SIZE_LIMIT : 52428800
    # FILE_STORAGE_BACKEND_PATH: "/var/lib/storage" # unused with S3, but required config

    # optional
    # ENABLE_IMAGE_TRANSFORMATION: "true"
    # IMGPROXY_URL: http://imgproxy:5001
  }
}
