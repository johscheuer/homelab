variable kubernetes_version {
  type    = string
  default = "1.18.6"
}

variable img_src {
  type    = string
  default = "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64-disk-kvm.img"
}

variable count_worker {
  type = number
  default = 3
}
