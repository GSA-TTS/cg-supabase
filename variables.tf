variable "cf_org_name" {
  type        = string
  description = "name of the Cloud Foundry organization to configure"
}

variable "cf_space_name" {
  type        = string
  description = "name of the Cloud Foundry space to configure"
}

variable "database_plan" {
  type        = string
  description = "name of the cloud.gov RDS service plan name to create"
  default     = "micro-psql"
}

variable "s3_plan_name" {
  type        = string
  description = "name of the cloud.gov S3 service plan to create"
  default     = "basic"
}

variable "database_service_instance_name" {
  type        = string
  description = "Name of an existing cloud.gov RDS service instance to use instead of creating one. Empty creates a new instance."
  default     = ""
}

variable "s3_service_instance_name" {
  type        = string
  description = "Name of an existing cloud.gov S3 service instance to use instead of creating one. Empty creates a new instance."
  default     = ""
}

variable "image_tag" {
  type        = string
  description = "Tag to use for ghcr.io/gsa-tts/cg-supabase service images. Defaults to the main-branch scanned tag."
  default     = "scanned"
}

# ---------------------------------------------------------------------------
# Cloud Foundry authentication — provide service-account credentials,
# username/password credentials, or neither to use CF CLI config fallback.
# ---------------------------------------------------------------------------

# Option A: Service account (OAuth2 client credentials)
variable "cf_client_id" {
  type        = string
  description = "cloud.gov OAuth2 client ID (service account). Leave empty when using username/password or CF CLI config fallback."
  default     = ""
}

variable "cf_client_secret" {
  type        = string
  description = "cloud.gov OAuth2 client secret (service account)."
  default     = ""
  sensitive   = true
}

# Option B: Username/password (legacy)
variable "cf_user" {
  type        = string
  description = "cloud.gov deployer account username. Leave empty when using service-account auth or CF CLI config fallback."
  default     = ""
}

variable "cf_password" {
  type        = string
  description = "cloud.gov deployer account password."
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Supabase JWT secrets — all optional; auto-generated if omitted.
# ---------------------------------------------------------------------------
variable "jwt_secret" {
  type        = string
  description = "40-char JWT signing secret. Auto-generated if empty."
  default     = ""
  sensitive   = true
}

variable "anon_key" {
  type        = string
  description = "JWT for the anon role. Auto-generated from jwt_secret if empty."
  default     = ""
  sensitive   = true
}

variable "service_role_key" {
  type        = string
  description = "JWT for the service_role role. Auto-generated from jwt_secret if empty."
  default     = ""
  sensitive   = true
}

variable "api_instances" {
  type        = number
  description = "the number of instances of the api application to run"
  default     = 1
}

variable "api_memory" {
  type        = string
  description = "the memory limit in megabytes for each api application instance"
  default     = "256M"
}

variable "auth_instances" {
  type        = number
  description = "the number of instances of the auth application to run"
  default     = 1
}

variable "auth_memory" {
  type        = string
  description = "the memory limit in megabytes for each auth application instance"
  default     = "128M"
}

variable "meta_instances" {
  type        = number
  description = "the number of instances of the meta application to run"
  default     = 1
}

variable "meta_memory" {
  type        = string
  description = "the memory limit in megabytes for each meta application instance"
  default     = "128M"
}

variable "rest_instances" {
  type        = number
  description = "the number of instances of the postgrest application to run"
  default     = 1
}

variable "rest_memory" {
  type        = string
  description = "the memory limit in megabytes for each postgrest application instance"
  default     = "128M"
}

variable "storage_instances" {
  type        = number
  description = "the number of instances of the storage application to run"
  default     = 1
}

variable "storage_memory" {
  type        = string
  description = "the memory limit in megabytes for each storage application instance"
  default     = "128M"
}

variable "studio_instances" {
  type        = number
  description = "the number of instances of the studio application to run"
  default     = 1
}

variable "studio_memory" {
  type        = string
  description = "the memory limit in megabytes for each studio application instance"
  default     = "128M"
}
