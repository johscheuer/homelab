resource "libvirt_pool" "kubernetes" {
  name = "kubernetes"
  type = "dir"
  path = "/etc/kubernetes-libvirt-pool"
}

# FIXME: pull only once on the remote machine!
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

// FIXME Add public ssh key
data "template_file" "user_data" {
  template = <<EOF
#cloud-config
disable_root: 0
ssh_pwauth: true
chpasswd:
  list: |
     root:password
  expire: False
users:
  - name: root
    ssh-authorized-keys:
      - ${file(pathexpand("~/.ssh/id_rsa.pub"))}
  - name: ubuntu
    ssh-authorized-keys:
      - ${file(pathexpand("~/.ssh/id_rsa.pub"))}
growpart:
  mode: auto
  devices: ['/']
EOF
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# FIXME: Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.kubernetes.name
}

# Create the machine
resource "libvirt_domain" "master" {
  name       = "master"
  memory     = "4096"
  vcpu       = 1
  qemu_agent = true
  autostart  = true

  cloudinit = libvirt_cloudinit_disk.commoninit.id

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

  cloudinit = libvirt_cloudinit_disk.commoninit.id

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

// FIXME: output ips -> used later for ansible
