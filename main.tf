data "cloudfoundry_space" "target" {
  name = var.cf_space_name
  org  = data.cloudfoundry_org.target.id
}

data "cloudfoundry_org" "target" {
  name = var.cf_org_name
}

module "supabase" {
  source        = "./supabase"
  cf_org_name   = var.cf_org_name
  cf_space_name = var.cf_space_name
  cf_space_id   = data.cloudfoundry_space.target.id
  https_proxy   = var.https_proxy
  app_name      = var.app_name

  jwt_secret       = var.jwt_secret
  anon_key         = var.anon_key
  service_role_key = var.service_role_key

  database_plan     = var.database_plan
  rest_instances    = var.rest_instances
  storage_instances = var.storage_instances
}

