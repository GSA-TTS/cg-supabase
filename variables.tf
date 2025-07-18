variable "cf_user" {
  type        = string
  description = "cloud.gov deployer account user"
}

variable "cf_password" {
  type        = string
  description = "secret; cloud.gov deployer account password"
  sensitive   = true
}

variable "cf_org_name" {
  description = "The name of the Cloud Foundry organization"
  type        = string
}

variable "cf_space_name" {
  description = "The name of the Cloud Foundry space"
  type        = string
}

variable "cf_space_id" {
  description = "The ID of the Cloud Foundry space"
  type        = string
}

variable "https_proxy" {
  description = "HTTPS proxy configuration"
  type        = string
}

variable "s3_id" {
  description = "S3 bucket ID for storage"
  type        = string
}

variable "logdrain_id" {
  description = "Log drain service ID"
  type        = string
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
  default     = "micro-psql"
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

variable "disk_quota" {
  description = "Disk quota in MB for applications"
  type        = number
  default     = 1024
}
