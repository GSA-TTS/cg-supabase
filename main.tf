module "supabase" {
  source        = "./supabase"
  cf_org_name   = "gsa-tts-oros-sorndashboard"
  cf_space_name = "supabase"

  # TODO - Make use of injected proxy, logdrain, S3, and Postgres info
  # https_proxy       = module.https-proxy.https_proxy
  # s3_id             = module.s3-private.bucket_id
  # logdrain_id       = module.cg-logshipper.logdrain_service_id

  jwt_secret       = var.jwt_secret
  anon_key         = var.anon_key
  service_role_key = var.service_role_key

  database_plan     = "micro-psql"
  api_instances     = 1
  meta_instances    = 1
  rest_instances    = 1
  storage_instances = 1
  studio_instances  = 1
}
