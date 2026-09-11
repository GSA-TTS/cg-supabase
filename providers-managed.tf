terraform {
  required_version = "~> 1.0"

  backend "local" {}

  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry/cloudfoundry"
      version = "~> 1.18.0"
    }
    jwt = {
      source  = "camptocamp/jwt"
      version = "~>1.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Cloud Foundry provider — authentication options:
#
#   Option A  Service account (CI/CD — recommended for automation):
#     export TF_VAR_cf_client_id="..."
#     export TF_VAR_cf_client_secret="..."
#
#   Option B  Username/password (legacy):
#     export TF_VAR_cf_user="..."
#     export TF_VAR_cf_password="..."
#
#   Option C  CF CLI config fallback (interactive SSO):
#     cf login -a https://api.fr.cloud.gov --sso
#     # Leave the credential variables empty; the provider reads CF CLI config.
# ---------------------------------------------------------------------------
provider "cloudfoundry" {
  api_url          = "https://api.fr.cloud.gov"
  user             = var.cf_user != "" ? var.cf_user : null
  password         = var.cf_password != "" ? var.cf_password : null
  cf_client_id     = var.cf_client_id != "" ? var.cf_client_id : null
  cf_client_secret = var.cf_client_secret != "" ? var.cf_client_secret : null
}
