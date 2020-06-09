# Nuc setup

## Base OS

Ubuntu focal (20.04):

- ..

### Setup wireless network

```bash
sudo apt install wireless-tools wpasupplicant
```

sudo ip link set wlp58s0 up
sudo iwlist scan

Find the wlan interface: `ls -l /sys/class/net/`
Add the wlan config to `/etc/netplan/01-network-manager-all.yaml`

```yaml
network:
  version: 2
  wifis:
    wlp58s0:
      optional: true
      access-points:
        "SSID":
          password: "totalsecure"
      dhcp4: true
      dhcp6: true
```

Apply the config: `sudo netplan --debug apply` and reload the systemd unit: `sudo systemctl daemon-reload` and finally restart the service: `sudo systemctl restart netplan-wpa-wlp58s0.service` and check that the network is up: `sudo systemctl status netplan-wpa-wlp58s0.service`

## Setup libvirt

See also: [KVM Ubuntu](https://help.ubuntu.com/community/KVM/Installation#Installation):

```bash
sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

Setup the user:

```bash
sudo adduser $(id -un) libvirt
sudo adduser $(id -un) kvm
```

## Terraform

```bash
# Required for unzip
sudo apt install unzip -y
# Install terraform
curl -sLO https://releases.hashicorp.com/terraform/0.12.26/terraform_0.12.26_linux_amd64.zip
unzip terraform_0.12.26_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

## Golang

```bas
curl -sLO https://dl.google.com/go/go1.14.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go*.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' ~/.bashrc
```

## libvirt terraform provider

Prerequisite;

```bash
sudo apt install -y libvirt-dev make gcc mkisofs
```

Clone the resources:

```bash
mkdir -p ~/go/src/github.com/dmacvicar; cd ~/go/src/github.com/dmacvicar
git clone https://github.com/dmacvicar/terraform-provider-libvirt.git
cd terraform-provider-libvirt/
git checkout tags/v0.6.2
```

build the provider:

```bash
export CGO_ENABLED="1"
export GO111MODULE=on
export GOFLAGS=-mod=vendor
make install
```

Move the new complied plugin to the specified terraform plugin folder:

```bash
mkdir -p ~/.terraform.d/plugins/
mv ~/go/bin/terraform-provider-libvirt ~/.terraform.d/plugins/terraform-provider-libvirt_v0.6.2
```

## Test the setup

Create a workspace directory:

```bash
mkdir -p workspace
cd workspace
```

Now take th example from [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt/tree/master/examples/v0.12/ubuntu) and test the setup:

```bash
terraform init
sudo -E terraform apply
```

Set the following setting in `/etc/libvirt/qemu.conf`:

```bash
security_driver = "none"
```

now reload and restart libvirtd: `systemctl reload libvirtd && systemctl restart libvirtd`.
Connect to the VM: `virsh console ubuntu-terraform`.
Exit th console with: `ctrl+shift+]`.

## Useful libvirt commands

### Get th ip address of an instance

```bash
virsh net-list
virsh net-info default
virsh net-dhcp-leases default
```

or use:

```bash
virsh list --name | while read -r n
do
  [[ ! -z $n ]] && virsh domifaddr $n
done
```

## Setup Macbook (client)

Install the prerequisites for libvirt:

```bash
brew install cdrtools libvirt
```

Create the VM's: `terraform apply`

Connect to one of the VM's:

```bash
ssh -J jscheuermann@192.168.0.242 root@172.16.0.39
```

## Kubernetes dev setup

We have the following dev setup:

| name | vCPU | RAM | root disk | data disk |
|:-:|:-:|---|---|---|
| master | 2 | 4GB | 20GB | - |
| worker-0 | 2 | 8GB | 20GB | 80GB |
| worker-1 | 2 | 8GB | 20GB | 80GB |
| worker-2 | 2 | 8GB | 20GB | 80GB |
| total | 8 | 28GB | 80GB | 240GB (320GB total with root) |

BaseOS will be Ubuntu focal (20.04) for all machines (maybe I change this later on to something different)

### Networking

TODO: setup IPv6
-> document IP setup

- https://www.berrange.com/posts/2011/06/16/providing-ipv6-connectivity-to-virtual-guests-with-libvirt-and-kvm/
- https://libvirt.org/formatnetwork.html
- https://wiki.gentoo.org/wiki/QEMU/KVM_IPv6_Support
- https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Proxies_and_Jump_Hosts

Kubernetes DualStack + Endpoint Slices

host -> 172.16.0.0/24
-> how to access from outside (ssh tunnel?)

### Cluster Setup

--> metallb + ingress
--> Prometheus
--> Dualstack
--> Storage rook.io (Ceph)

## TODO

-> https://libvirt.org/drvqemu.html
-> take a look at: https://github.com/kimchi-project/kimchi
-> https://johnsiu.com/blog/macos-kvm-remote-connect/
-> `LIBVIRT_DEFAULT_URI='qemu:///system'`
