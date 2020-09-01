resource "libvirt_pool" "kubernetes" {
  name = "kubernetes"
  type = "dir"
  path = "/etc/kubernetes-libvirt-pool"
}

resource "libvirt_volume" "base" {
  name   = "base.qcow2"
  pool   = libvirt_pool.kubernetes.name
  source = var.img_src
  format = "qcow2"
}

resource "libvirt_volume" "master" {
  name           = "master.qcow2"
  pool           = libvirt_pool.kubernetes.name
  base_volume_id = libvirt_volume.base.id
  format         = "qcow2"
  # 20GB
  size = 21474836480
}

resource "libvirt_volume" "worker" {
  count          = 3
  name           = "worker_${count.index}.qcow2"
  pool           = libvirt_pool.kubernetes.name
  base_volume_id = libvirt_volume.base.id
  format         = "qcow2"
  # 20GB
  size = 21474836480
}
// Data disk used for Storage
resource "libvirt_volume" "worker_data" {
  count = 3
  name  = "worker_data_${count.index}.qcow2"
  pool  = libvirt_pool.kubernetes.name
  # 80 GB
  size = 85899345920
}

resource "libvirt_cloudinit_disk" "master_commoninit" {
  name = "master_commoninit.iso"
  user_data = templatefile("${path.module}/cloud_init.yml",
    {
      hostname           = "master",
      kubernetes_version = var.kubernetes_version
  })
  pool = libvirt_pool.kubernetes.name
}

resource "libvirt_cloudinit_disk" "worker_commoninit" {
  count = 3
  name  = "worker_${count.index}_commoninit.iso"
  user_data = templatefile("${path.module}/cloud_init.yml",
    {
      hostname           = "worker-${count.index}",
      kubernetes_version = var.kubernetes_version
  })
  pool = libvirt_pool.kubernetes.name
}

# Create the machine
resource "libvirt_domain" "master" {
  name       = "master"
  memory     = "4096"
  vcpu       = 2
  qemu_agent = true
  autostart  = true

  cloudinit = libvirt_cloudinit_disk.master_commoninit.id

  network_interface {
    network_name   = libvirt_network.kube_network.name
    hostname       = "master"
    addresses      = ["172.16.0.2"] #, "fd4a:fc40:8cfb::2"]
    wait_for_lease = true
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.master.id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

resource "libvirt_domain" "worker" {
  name       = "worker-${count.index}"
  memory     = "8192"
  vcpu       = 4
  qemu_agent = true
  count      = var.count_worker
  autostart  = true

  cloudinit = element(libvirt_cloudinit_disk.worker_commoninit.*.id, count.index)

  disk {
    volume_id = element(libvirt_volume.worker.*.id, count.index)
  }

  disk {
    volume_id = element(libvirt_volume.worker_data.*.id, count.index)
  }

  network_interface {
    network_name   = libvirt_network.kube_network.name
    hostname       = "worker-${count.index}"
    addresses      = ["172.16.0.1${count.index}"] #, "fd4a:fc40:8cfb::1${count.index}"]
    wait_for_lease = true
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "master_ip" {
  value = libvirt_domain.master.*.network_interface.0.addresses
}

output "worker_ips" {
  value = libvirt_domain.worker.*.network_interface.0.addresses
}

output "kubernetes_version" {
  value = var.kubernetes_version
}
