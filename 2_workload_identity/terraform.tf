terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.5.1"
    }
  }
}

provider "vault" {
  # Configuration options
}


provider "nomad" {
  # Configuration options
}