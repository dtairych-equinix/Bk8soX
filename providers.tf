terraform {
    required_providers {
        equinix = {
            source  = "equinix/equinix"
            version = "latest"
        }
    }
}

provider "equinix" {
    auth_token = var.auth_token
}