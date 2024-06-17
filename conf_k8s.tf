resource "null_resource" "update_master_hosts" {
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./private_key")
    host        = equinix_metal_device.master.access_public_ipv4
  }

  provisioner "file" {
    source      = "./hosts"
    destination = "/tmp/hosts"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cat /tmp/hosts >> /etc/hosts"
    ]
  }

  depends_on = [ data.local_file.hosts ]
}

resource "null_resource" "update_worker_hosts" {
  count = var.worker_count
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("./private_key")
    host        = equinix_metal_device.workers[count.index].access_public_ipv4
  }

  provisioner "file" {
    source      = "./hosts"
    destination = "/tmp/hosts"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cat /tmp/hosts >> /etc/hosts"
    ]
  }

  depends_on = [ data.local_file.hosts ]
}