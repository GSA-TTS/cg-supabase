# ---------------------------------------------------------------------------
# Cloud Foundry authentication — provide ONE of the three option groups below.
# ---------------------------------------------------------------------------

# Option A: Service account (OAuth2 client credentials)
variable "cf_client_id" {
  type        = string
  description = "cloud.gov OAuth2 client ID (service account). Leave empty when using Option B or C."
  default     = ""
}

variable "cf_client_secret" {
  type        = string
  description = "cloud.gov OAuth2 client secret (service account)."
  default     = ""
  sensitive   = true
}

# Option B: SSO passcode (interactive)
variable "cf_sso_passcode" {
  type        = string
  description = "One-time SSO passcode from 'cf login --sso'. Leave empty when using Option A or C."
  default     = ""
  sensitive   = true
}

# Option C: Username/password (legacy)
variable "cf_user" {
  type        = string
  description = "cloud.gov deployer account username. Leave empty when using Option A or B."
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
