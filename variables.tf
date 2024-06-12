variable "auth_token" {
  description = "Equinix Metal authentication token"
  type = string
  sensitive = true
}

variable "organization_id" {
  description = "Equinix Metal organization id"
  type = string
  sensitive = true
}

variable "worker_count" {
  description = "The number of worker nodes in the cluster"
  type = number
  default = 3
}