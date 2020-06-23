resource "libvirt_pool" "kubernetes" {
  name = "kubernetes"
  type = "dir"
  path = "/etc/kubernetes-libvirt-pool"
}

# We fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu.qcow2"
  pool   = libvirt_pool.kubernetes.name
  source = "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64-disk-kvm.img"
  format = "qcow2"
}

resource "libvirt_volume" "master" {
  name           = "master.qcow2"
  pool           = libvirt_pool.kubernetes.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  # 20GB
  size = 21474836480
}

resource "libvirt_volume" "worker" {
  count          = 3
  name           = "worker_${count.index}.qcow2"
  pool           = libvirt_pool.kubernetes.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  # 20GB
  size = 21474836480
}
// Data disk used for Ceph
resource "libvirt_volume" "worker_data" {
  count = 3
  name  = "worker_data_${count.index}.qcow2"
  pool  = libvirt_pool.kubernetes.name
  # 80 GB
  size = 85899345920
}

// FIXME: (add as variable): kubernetes_version
// FIXME: https://github.com/inovex/kubernetes-on-openstack/blob/master/scripts/master.cfg.tpl#L837
data "template_file" "master_user_data" {
  template = "${file("${path.module}/cloud_init.yml")}"
    vars = {
      hostname = "master"
  }
}

data "template_file" "worker_user_data" {
  count = 3
  template = "${file("${path.module}/cloud_init.yml")}"
  vars = {
    hostname = "worker-${count.index}"
  }
}

resource "libvirt_cloudinit_disk" "master_commoninit" {
  name           = "master_commoninit.iso"
  user_data      = data.template_file.master_user_data.rendered
  pool           = libvirt_pool.kubernetes.name
}

resource "libvirt_cloudinit_disk" "worker_commoninit" {
  count = 3
  name           = "worker_${count.index}_commoninit.iso"
  user_data      = element(data.template_file.worker_user_data.*.rendered, count.index)
  pool           = libvirt_pool.kubernetes.name
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
  vcpu       = 2
  qemu_agent = true
  # FIXME move this into a variable
  count     = 3
  autostart = true

  cloudinit = element(libvirt_cloudinit_disk.worker_commoninit.*.id, count.index)

  disk {
    volume_id = element(libvirt_volume.worker.*.id, count.index)
  }

  disk {
    volume_id = element(libvirt_volume.worker_data.*.id, count.index)
  }

  network_interface {
    network_name   = libvirt_network.kube_network.name
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
