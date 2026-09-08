module "supabase" {
  source        = "./supabase"
  cf_org_name   = var.cf_org_name
  cf_space_name = var.cf_space_name

  # JWT secrets are optional — omit to auto-generate, or provide to reuse existing values.
  # See vars.auto.tfvars-example for the full set of configurable options.
  jwt_secret       = var.jwt_secret
  anon_key         = var.anon_key
  service_role_key = var.service_role_key

  database_plan = var.database_plan

  api_instances     = var.api_instances
  api_memory        = var.api_memory
  auth_instances    = var.auth_instances
  auth_memory       = var.auth_memory
  meta_instances    = var.meta_instances
  meta_memory       = var.meta_memory
  rest_instances    = var.rest_instances
  rest_memory       = var.rest_memory
  storage_instances = var.storage_instances
  storage_memory    = var.storage_memory
  studio_instances  = var.studio_instances
  studio_memory     = var.studio_memory
}
