resource "tls_private_key" "ssh_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "local_file" "private_key" {
  content = tls_private_key.ssh_key.private_key_openssh
  filename = "./locals/private_key"
  file_permission = "0600"
}

resource "local_file" "public_key" {
  content = tls_private_key.ssh_key.public_key_openssh
  filename = "./locals/public_key"
  file_permission = "0600"
}

data "http" "cloud_init" {
  url = "https://raw.githubusercontent.com/dtairych/k8s-cloudinit/main/cloud-init.yml"
}

resource "local_file" "hosts" {
  content = templatefile("./locals/hosts.tftpl", {
    instances = [
        for idx, instance in equinix_metal_device.workers :
        {
            ip = instance.access_public_ipv4
            hostname = instance.hostname
        }
    ],
    master_ip = equinix_metal_device.master.access_public_ipv4,
    master_hostname = equinix_metal_device.master.hostname
  })

  filename = "./locals/hosts"
  

}