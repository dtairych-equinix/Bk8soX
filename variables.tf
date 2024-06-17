variable "auth_token" {
  description = "Equinix Metal authentication token"
  type = string
  sensitive = true
}

variable "org_id" {
  description = "Equinix Metal organization id"
  type = string
  sensitive = true
}

variable "worker_count" {
  description = "The number of worker nodes in the cluster"
  type = number
  default = 3
}

variable "metro" {
    description = "Metro to deploy the cluster in"
    type = string
    default = "am"
}

variable "domain" {
    description = "Domain name of the cluster"
    type = string
    default = "k8s.dev"
}