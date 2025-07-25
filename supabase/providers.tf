terraform {
  required_version = "~> 1.0"
  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry-community/cloudfoundry"
      version = "0.53.1"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }

    github = {
      source  = "integrations/github"
      version = "~>6.2"
    }
  }
}

# Provider configuration inherits from parent module
# Uses CF_OAUTH_TOKEN environment variable for authentication

provider "cloudfoundry" {
  api_url = "https://api.fr.cloud.gov"
  # Authentication will use CF_ACCESS_TOKEN environment variable
}

provider "docker" {
}

