module "supabase" {
  source        = "./supabase"
  cf_org_name   = "gsa-tts-oros-sorndashboard"
  cf_space_name = "supabase"

  # JWT secrets are optional — omit to auto-generate, or provide to reuse existing values.
  # See vars.auto.tfvars-example for the full set of configurable options.
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
