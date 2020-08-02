# Nuc setup

## Base OS

Ubuntu focal (20.04).

### Requirements

Install [unattended-upgrades](https://help.ubuntu.com/community/AutomaticSecurityUpdates):

```bash
sudo apt install unattended-upgrades
```

(Optional) Install [img](https://github.com/genuinetools/img/releases/download):

```bash
sudo apt install uidmap libseccomp-dev

curl -sLO https://github.com/genuinetools/img/releases/download/v0.5.7/img-linux-amd64
chmod +x img-linux-amd64
sudo mv img-linux-amd64 /usr/local/bin/img
```

### Remote unlock LUKS

For more details see [this blog post](https://hamy.io/post/0009/how-to-install-luks-encrypted-ubuntu-18.04.x-server-and-enable-remote-unlocking).

```bash
sudo apt-get -y install dropbear-initramfs
```

Add some sane options for dropbear:

```bash
sudo sed -i s/#DROPBEAR_OPTIONS=.*/DROPBEAR_OPTIONS='"-s -j -k -I 60"'/ /etc/dropbear-initramfs/config
```

Copy the authorized ssh keys (I assume you logged in once over ssh):

```bash
sudo cp .ssh/authorized_keys /etc/dropbear-initramfs/authorized_keys
```

In order to limit the ssh to only unlock the luks I prefixed the entries with:

```bash
no-port-forwarding,no-agent-forwarding,no-x11-forwarding,command="/bin/cryptroot-unlock"
```

In te end generate the new initramfs:

```bash
sudo update-initramfs -u
```

Now we can unlock luks with: `ssh root@192.168.0.25`.

In order to prevent the `Host key verification failed` error we can add the following block to the ssh config:

```bash
Host 192.168.0.25
   StrictHostKeyChecking no
   IdentityFile ~/.ssh/id_rsa
   IdentitiesOnly yes
```

### Wake on LAN

Check if it is already activated otherwise [set it up](https://www.intel.de/content/www/de/de/support/articles/000027615/intel-nuc.html)

```bash
sudo ethtool eno1
# If the output contains "Wake-on: g" wake on lan is activated.
```

Adjust the [netplan](https://wiki.ubuntuusers.de/Netplan/) config:

```yaml
# /etc/netplan/00-installer-config.yaml
network:
  ethernets:
    eno1:
      match:
        macaddress: <mac>
      dhcp4: true
      dhcp6: true
      wakeonlan: true
      accept-ra: true
  version: 2
```

Apply the changes: `sudo netplan --debug apply`

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
      accept-ra: true
```

Apply the config: `sudo netplan --debug apply` and reload the systemd unit: `sudo systemctl daemon-reload` and finally restart the service: `sudo systemctl restart netplan-wpa-wlp58s0.service` and check that the network is up: `sudo systemctl status netplan-wpa-wlp58s0.service`

### IPv6 router advertisements

If you want to use IPv6 [stateless address autoconfiguration (slaac)](https://en.wikipedia.org/wiki/IPv6_address#Stateless_address_autoconfiguration) on the host and also run some virtual machines you need to modify the [accept_ra](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt) value to `2`:

```bash
sudo tee /etc/sysctl.d/ipv6.conf <<< 'net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.accept_ra = '
```

### IP forwarding

Set the `sysctl` settings for packet forwarding (e.g. use tout Hypervisor as router):

```bash
sudo tee /etc/sysctl.d/vm.conf <<< 'net.ipv4.ip_forward = 1
net.ipv6.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1'
```

Set a forwarding rule:

```bash
iptables -I FORWARD -o k8snet-br -d 172.16.0.0/24 -j ACCEPT
```

Install `iptables-persistent` to make the change persistent:

```bash
sudo apt-get install iptables-persistent
```

During the setup all rules will be persisted but you can also store the rules with the following command:

```bash
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
```

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
ssh -J jscheuermann@192.168.0.25 root@172.16.0.39
```

## Cleanup of Hypervisor

Stop unused service `snapd`

```bash
sudo systemctl disable snapd
```

## Debugging tools

Install the `sysstat` package.

## Further reading

- [macos-kvm-remote-connect](https://johnsiu.com/blog/macos-kvm-remote-connect)
