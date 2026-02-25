terraform {
  required_version = "~> 1.0"
  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry-community/cloudfoundry"
      version = "~>0.53.1"
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
# Cloud Foundry provider — three authentication options (use one):
#
#   Option A  Service account (CI/CD — recommended for automation):
#     export TF_VAR_cf_client_id="..."
#     export TF_VAR_cf_client_secret="..."
#
#   Option B  SSO passcode (interactive login):
#     cf login -a https://api.fr.cloud.gov --sso   # grab one-time passcode
#     export TF_VAR_cf_sso_passcode="..."
#
#   Option C  Username/password (legacy):
#     export TF_VAR_cf_user="..."
#     export TF_VAR_cf_password="..."
# ---------------------------------------------------------------------------
provider "cloudfoundry" {
  api_url          = "https://api.fr.cloud.gov"
  user             = var.cf_user
  password         = var.cf_password
  sso_passcode     = var.cf_sso_passcode
  cf_client_id     = var.cf_client_id
  cf_client_secret = var.cf_client_secret
}
