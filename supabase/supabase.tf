locals {
  # Names to use for each app (matches upstream docker-compose.yml)
  api_app_name     = "supabase-api"
  meta_app_name    = "supabase-meta"
  rest_app_name    = "supabase-rest"
  storage_app_name = "supabase-storage"
  studio_app_name  = "supabase-studio"

  # A generated slug for use in domain names to avoid collisions, etc.
  slug = "-${trim(replace(replace(lower(var.cf_space_name), "/[^\\w_]/", "-"), "/-+/", "-"), "-")}"

}

# The beating heart of all Supabase services is a Postgres database
module "database" {
  source        = "github.com/GSA-TTS/terraform-cloudgov//database?ref=v2.0.0"
  cf_org_name   = var.cf_org_name
  cf_space_name = var.cf_space_name
  name          = "supabase-db"
  rds_plan_name = var.database_plan
}

# Make sure the space can reach brokered services
data "cloudfoundry_asg" "trusted-local-networks" {
  name = "trusted_local_networks_egress"
}

data "cloudfoundry_space" "space" {
  org_name = var.cf_org_name
  name     = var.cf_space_name
}

# TODO: This doesn't seem to be working; it gets a 403 response
# resource "cloudfoundry_space_asgs" "asgs" {
#   space = data.cloudfoundry_space.space.id
#   staging_asgs = [ data.cloudfoundry_asg.trusted-local-networks.id ]
#   running_asgs = [ data.cloudfoundry_asg.trusted-local-networks.id ]
# }

# Stuff used for apps in this space
data "cloudfoundry_space" "apps" {
  org_name = var.cf_org_name
  name     = var.cf_space_name
}

data "cloudfoundry_domain" "public" {
  name = "app.cloud.gov"
}

data "cloudfoundry_domain" "private" {
  name = "apps.internal"
}
