variable "cf_org_name" {
  description = "The name of the Cloud Foundry organization"
  type        = string
}

variable "cf_space_name" {
  description = "The name of the Cloud Foundry space"
  type        = string
}

variable "https_proxy" {
  description = "HTTPS proxy configuration"
  type        = string
  default     = ""
}

variable "app_name" {
  description = "Base name for the Supabase application components"
  type        = string
  default     = "supabase"
}

variable "jwt_secret" {
  description = "JWT secret key for Supabase authentication"
  type        = string
  sensitive   = true
}

variable "anon_key" {
  description = "Anonymous key for Supabase"
  type        = string
  sensitive   = true
}

variable "service_role_key" {
  description = "Service role key for Supabase"
  type        = string
  sensitive   = true
}

variable "database_plan" {
  description = "Database plan for PostgreSQL service"
  type        = string
  default     = "dev-psql"
}

variable "rest_instances" {
  description = "Number of PostgREST instances"
  type        = number
  default     = 1
}

variable "storage_instances" {
  description = "Number of Supabase storage instances"
  type        = number
  default     = 1
}

