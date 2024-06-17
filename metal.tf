resource "equinix_metal_ssh_key" "k8s" {
  name = "k8sCluster"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

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

  depends_on = [ equinix_metal_ssh_key.k8s ]
}

resource "equinix_metal_device" "workers" {
  count = var.worker_count
  hostname = "worker-${count.index}.k8s.dev"
  plan             = "m3.small.x86"
  metro            = "am"
  operating_system = "debian_12"
  billing_cycle    = "hourly"
  project_id       = equinix_metal_project.k8s.id

  user_data = data.http.cloud_init.body

  depends_on = [ equinix_metal_ssh_key.k8s ]
}
