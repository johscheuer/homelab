resource "libvirt_network" "kube_network" {
  autostart = true
  name      = "k8snet"
  mode      = "nat"
  domain    = "k8s.local"
  # IPv6 ULA address: https://tools.ietf.org/html/rfc4193
  addresses = ["172.16.0.0/24", "fd4a:fc40:8cfb::/64"]

  dhcp {
    enabled = false
  }

  bridge    = "k8snet-br"
  dns {
    enabled    = true
    local_only = true
    # FIXME: setup dns entries for master/worker
  }
}
