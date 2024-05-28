variable "cf_user" {
  type        = string
  description = "cloud.gov deployer account user"
}

variable "cf_password" {
  type        = string
  description = "secret; cloud.gov deployer account password"
  sensitive   = true
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
