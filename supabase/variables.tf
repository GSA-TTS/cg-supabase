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
  # See https://cloud.gov/docs/services/relational-database/#plans
  default = "medium-gp-psql-redundant"
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

variable "api_instances" {
  type        = number
  description = "the number of instances of the api application to run (default: 2)"
  default     = 2
}

variable "api_memory" {
  type        = string
  description = "the memory limit in megabytes for each api application instance (default: 256)"
  default     = "256M"
}

variable "auth_instances" {
  type        = number
  description = "the number of instances of the auth application to run (default: 2)"
  default     = 2
}

variable "auth_memory" {
  type        = string
  description = "the memory limit in megabytes for each auth application instance (default: 128)"
  default     = "128M"
}

variable "meta_instances" {
  type        = number
  description = "the number of instances of the meta application to run (default: 2)"
  default     = 2
}

variable "meta_memory" {
  type        = string
  description = "the memory limit in megabytes for each postgrest instance (default: 128)"
  default     = "128M"
}

variable "rest_instances" {
  type        = number
  description = "the number of instances of the postgrest application to run (default: 2)"
  default     = 2
}

variable "rest_memory" {
  type        = string
  description = "the memory limit in megabytes for each postgrest instance (default: 128)"
  default     = "128M"
}

variable "storage_instances" {
  type        = number
  description = "the number of instances of the storage application to run (default: 2)"
  default     = 2
}

variable "storage_memory" {
  type        = string
  description = "the memory limit in megabytes for each storage instance (default: 128)"
  default     = "128M"
}

variable "studio_instances" {
  type        = number
  description = "the number of instances of the studio application to run (default: 2)"
  default     = 2
}

variable "studio_memory" {
  type        = string
  description = "the memory limit in megabytes for each studio instance (default: 640)"
  default     = "640M"
}

variable "jwt_secret" {
  type        = string
  description = "40-char JWT signing secret. If empty, one is auto-generated via random_password."
  default     = ""
  sensitive   = true
}

variable "anon_key" {
  type        = string
  description = "JWT for the anon role. If empty, auto-generated from jwt_secret using the camptocamp/jwt provider."
  default     = ""
  sensitive   = true
}

variable "service_role_key" {
  type        = string
  description = "JWT for the service_role role. If empty, auto-generated from jwt_secret using the camptocamp/jwt provider."
  default     = ""
  sensitive   = true
}

variable "docker_username" {
  type        = string
  description = "Docker Hub username for authenticated image pulls (bypasses anonymous rate limits). Optional."
  default     = ""
}

variable "docker_password" {
  type        = string
  description = "Docker Hub password or PAT for authenticated image pulls. Optional."
  default     = ""
  sensitive   = true
}

variable "logflare_api_key" {
  type        = string
  description = "the API key for logflare"
  default     = "your-super-secret-and-long-logflare-key"
  sensitive   = true
}

variable "logflare_logger_backend_api_key" {
  type        = string
  description = "the API key for logflare loggers to talk to the backend"
  default     = "your-super-secret-and-long-logflare-key"
  sensitive   = true
}

