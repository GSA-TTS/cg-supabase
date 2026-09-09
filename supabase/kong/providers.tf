terraform {
  required_version = "~> 1.0"
  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry/cloudfoundry"
      version = "~> 1.18.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "~>2.3"
    }
  }
}

