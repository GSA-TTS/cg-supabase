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

variable "api_instances" {
  type        = number
  description = "the number of instances of the api application to run (default: 2)"
  default     = 2
}

variable "api_memory" {
  type        = string
  description = "the memory limit in megabytes for each api application instance (default: 256)"
  default     = "256"
}

variable "meta_instances" {
  type        = number
  description = "the number of instances of the meta application to run (default: 2)"
  default     = 2
}

variable "meta_memory" {
  type        = string
  description = "the memory limit in megabytes for each postgrest instance (default: 128)"
  default     = "128"
}

variable "rest_instances" {
  type        = number
  description = "the number of instances of the postgrest application to run (default: 2)"
  default     = 2
}

variable "rest_memory" {
  type        = string
  description = "the memory limit in megabytes for each postgrest instance (default: 128)"
  default     = "128"
}

variable "storage_instances" {
  type        = number
  description = "the number of instances of the storage application to run (default: 2)"
  default     = 2
}

variable "storage_memory" {
  type        = string
  description = "the memory limit in megabytes for each storage instance (default: 128)"
  default     = "128"
}

variable "studio_instances" {
  type        = number
  description = "the number of instances of the studio application to run (default: 2)"
  default     = 2
}

variable "studio_memory" {
  type        = string
  description = "the memory limit in megabytes for each studio instance (default: 128)"
  default     = "128"
}

variable "jwt_secret" {
  type        = string
  description = "the JWT signing secret for TODO"
  sensitive   = true
}

variable "anon_key" {
  type        = string
  description = "the JWT signing secret for TODO"
  sensitive   = true
}

variable "service_role_key" {
  type        = string
  description = "the JWT signing secret for TODO"
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

