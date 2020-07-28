terraform {
  required_version = ">= 0.12"
}

provider "libvirt" {
  //uri = "qemu:///system"
  uri = "qemu+ssh://jscheuermann@192.168.0.25/system?socket=/var/run/libvirt/libvirt-sock"
}
