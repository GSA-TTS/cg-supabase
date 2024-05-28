terraform {
  required_version = "~> 1.0"
  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry-community/cloudfoundry"
      version = "~>0.53.1"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~>3.0.2"
    }

    github = {
      source  = "integrations/github"
      version = "~>4.0"
    }
  }
}

