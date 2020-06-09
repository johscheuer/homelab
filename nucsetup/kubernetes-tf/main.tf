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

// https://cloudinit.readthedocs.io/en/latest/topics/examples.html
// FIXME: (add as variable): kubernetes_version
// FIXME: auto bootstrap Kubernetes cluster with kubeadm file
// FIXME: https://github.com/inovex/kubernetes-on-openstack/blob/master/scripts/master.cfg.tpl#L837
// FIXME: unattended upgrades: https://www.brightbox.com/docs/guides/unattended-upgrades/
data "template_file" "user_data" {
  template = <<EOF
#cloud-config
repo_update: true
repo_upgrade: all
package_upgrade: true

packages:
  - apt-transport-https
  - util-linux
  - kubernetes-cni
  - [kubelet, "1.18.3-00"]
  - [kubeadm, "1.18.3-00"]
  - [kubectl, "1.18.3-00"]
  - jq
  - socat
  - conntrack
  - ipset
  - libseccomp2
  - containerd
  - chrony

write_files:
- content: |
    net.ipv4.ip_forward = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.bridge.bridge-nf-call-iptables = 1
  path: /etc/sysctl.d/k8s.conf
- content: |
    br_netfilter
  path: /etc/modules-load.d/k8s.conf

apt:
  preserve_sources_list: true
  sources:
    kubernetes.list:
      source: "deb http://apt.kubernetes.io/ kubernetes-xenial main"
      key: |
        -----BEGIN PGP PUBLIC KEY BLOCK-----
        Version: GnuPG v1

        mQENBFrBaNsBCADrF18KCbsZlo4NjAvVecTBCnp6WcBQJ5oSh7+E98jX9YznUCrN
        rgmeCcCMUvTDRDxfTaDJybaHugfba43nqhkbNpJ47YXsIa+YL6eEE9emSmQtjrSW
        IiY+2YJYwsDgsgckF3duqkb02OdBQlh6IbHPoXB6H//b1PgZYsomB+841XW1LSJP
        YlYbIrWfwDfQvtkFQI90r6NknVTQlpqQh5GLNWNYqRNrGQPmsB+NrUYrkl1nUt1L
        RGu+rCe4bSaSmNbwKMQKkROE4kTiB72DPk7zH4Lm0uo0YFFWG4qsMIuqEihJ/9KN
        X8GYBr+tWgyLooLlsdK3l+4dVqd8cjkJM1ExABEBAAG0QEdvb2dsZSBDbG91ZCBQ
        YWNrYWdlcyBBdXRvbWF0aWMgU2lnbmluZyBLZXkgPGdjLXRlYW1AZ29vZ2xlLmNv
        bT6JAT4EEwECACgFAlrBaNsCGy8FCQWjmoAGCwkIBwMCBhUIAgkKCwQWAgMBAh4B
        AheAAAoJEGoDCyG6B/T78e8H/1WH2LN/nVNhm5TS1VYJG8B+IW8zS4BqyozxC9iJ
        AJqZIVHXl8g8a/Hus8RfXR7cnYHcg8sjSaJfQhqO9RbKnffiuQgGrqwQxuC2jBa6
        M/QKzejTeP0Mgi67pyrLJNWrFI71RhritQZmzTZ2PoWxfv6b+Tv5v0rPaG+ut1J4
        7pn+kYgtUaKdsJz1umi6HzK6AacDf0C0CksJdKG7MOWsZcB4xeOxJYuy6NuO6Kcd
        Ez8/XyEUjIuIOlhYTd0hH8E/SEBbXXft7/VBQC5wNq40izPi+6WFK/e1O42DIpzQ
        749ogYQ1eodexPNhLzekKR3XhGrNXJ95r5KO10VrsLFNd8I=
        =TKuP
        -----END PGP PUBLIC KEY BLOCK-----

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
    sudo: ALL=(ALL) NOPASSWD:ALL
    gecos: ubuntu
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev]
    shell: /bin/bash
    ssh-authorized-keys:
      - ${file(pathexpand("~/.ssh/id_rsa.pub"))}
growpart:
  mode: auto
  devices: ['/']

runcmd:
- "systemctl restart systemd-modules-load.service"
- "sysctl --system"
EOF
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
}

# for more info about paramater check this out
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
  vcpu       = 2
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

output "master_ip" {
  value = libvirt_domain.master.*.network_interface.0.addresses
}

output "worker_ips" {
  value = libvirt_domain.worker.*.network_interface.0.addresses
}
