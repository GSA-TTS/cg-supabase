terraform {
  required_version = "~> 1.0"
  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry/cloudfoundry"
      version = "~> 1.18.0"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~>3.0.2"
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

