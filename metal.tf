resource "equinix_metal_project" "k8s" {
  name = "k8s Cluster"
  organization_id = var.organization_id
}

resource "equinix_metal_device" "master" {
  hostname         = "master.k8s.dev"
  plan             = "m3.small.x86"
  metro            = "am"
  operating_system = "debian_12"
  billing_cycle    = "hourly"
  project_id       = equinix_metal_project.k8s.id

  user_data = data.http.cloud_init.body
}

resource "equinix_metal_device" "workers" {
  count = var.worker_count
  hostname = "worker${count}.k8s.dev"
  plan             = "m3.small.x86"
  metro            = "am"
  operating_system = "debian_12"
  billing_cycle    = "hourly"
  project_id       = equinix_metal_project.k8s.id

  user_data = data.http.cloud_init.body
}