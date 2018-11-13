#!/bin/bash

set -eu
# expected to run on Ubuntu 18.04
# TODO move this to an Ansible script
# TODO run shellcheck

sudo apt-get install -y unzip tar btrfs-tools util-linux nfs-common ipvsadm socat conntrack ipset libseccomp2 # jq

#####################################################################################################
# Install Kata Containers                                                                           #
# https://github.com/kata-containers/documentation/blob/master/install/ubuntu-installation-guide.md #
#####################################################################################################
ARCH=$(arch)
sudo sh -c "echo 'deb http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/master/xUbuntu_$(lsb_release -rs)/ /' > /etc/apt/sources.list.d/kata-containers.list"
curl -sL "http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/master/xUbuntu_$(lsb_release -rs)/Release.key" | sudo apt-key add -
sudo -E apt-get update
sudo -E apt-get -y install kata-runtime kata-proxy kata-shim

#####################################################################################################
# Install containerd
# https://github.com/containerd/cri/blob/master/docs/installation.md
#####################################################################################################

curl -sLo /tmp/containerd.tar.gz "https://storage.googleapis.com/cri-containerd-release/cri-containerd-cni-1.2.0.linux-amd64.tar.gz"
sudo -E tar -C / -xzf /tmp/containerd.tar.gz
rm -f /tmp/containerd.tar.gz
sudo -E systemctl start containerd
sudo -E systemctl enable containerd

sudo mkdir -p /etc/containerd/
cat << EOT | sudo tee /etc/containerd/config.toml
[plugins]
    [plugins.cri.containerd]
      [plugins.cri.containerd.untrusted_workload_runtime]
        runtime_type = "io.containerd.runtime.v1.linux"
        runtime_engine = "/usr/bin/kata-runtime"
EOT


##
# TODO
#
##
# turn of swap
sudo -E swapoff -a
sudo sed '/swap/d' -i /etc/fstab

sudo -E modprobe ip_vs_rr
sudo -E modprobe ip_vs_wrr
sudo -E modprobe ip_vs_sh
sudo -E modprobe ip_vs
sudo -E modprobe br_netfilter
sudo -E modprobe nf_conntrack_ipv4

echo "ip_vs_rr" | sudo tee -a /etc/modules
echo "ip_vs_wrr" | sudo tee -a /etc/modules
echo "ip_vs_sh" | sudo tee -a /etc/modules
echo "ip_vs" | sudo tee -a /etc/modules
echo "br_netfilter" | sudo tee -a /etc/modules
echo "nf_conntrack_ipv4" | sudo tee -a /etc/modules

echo '1' | sudo tee -a /proc/sys/net/ipv4/ip_forward
echo '1' | sudo tee -a /proc/sys/net/bridge/bridge-nf-call-iptables
# CoreDNS doesn't like IPv6 -> https://github.com/coredns/coredns/issues/2087
echo '1' | sudo tee -a /proc/sys/net/ipv6/conf/default/disable_ipv6
echo '1' | sudo tee -a /proc/sys/net/ipv6/conf/all/disable_ipv6

sudo sh -c 'cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF'

#################################################################
# Install kubeadm, kubelet, kubectl                             #
# https://kubernetes.io/docs/setup/independent/install-kubeadm/ #
#################################################################


sudo -E apt-get update && sudo -E apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo -E apt-key add -
sudo sh -c 'cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF'
sudo -E apt-get update
sudo -E apt-get install -y kubelet=1.12.2-00 kubeadm=1.12.2-00 kubectl=1.12.2-00
apt-mark hold kubelet kubeadm kubectl

sudo sh -c 'cat <<EOF >/etc/kubernetes/kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.12.2
kubeProxy:
    config:
        mode: "ipvs"
kubeletConfiguration:
    baseConfig:
        authentication:
            anonymous:
                enabled: false
            x509:
                clientCAFile: /etc/kubernetes/pki/ca.crt
        cgroupDriver: systemd
        cgroupsPerQOS: true
        resolvConf: /run/systemd/resolve/resolv.conf
        cgroupRoot: "/"
networking:
    serviceSubnet: "10.96.0.0/16"
    dnsDomain: "cluster.local"
    podSubnet: "172.16.0.0/12"
nodeRegistration:
    criSocket: unix:///run/containerd/containerd.sock
    container-runtime: remote
    container-runtime-endpoint: unix:///run/containerd/containerd.sock
featureGates:
    Auditing: true
EOF'

sudo kubeadm init --config /etc/kubernetes/kubeadm.yaml --skip-token-print

##
# Init ..
#
######

mkdir -p "${HOME}/.kube"
sudo cp -i /etc/kubernetes/admin.conf "${HOME}/.kube/config"
sudo chown "$(whoami)" "${HOME}/.kube/config"

# Remove master taint because we only have one master :)
kubectl taint node node-role.kubernetes.io/master- --all

###
# Install Calico
# https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/calico#installing-with-the-kubernetes-api-datastore50-nodes-or-less
###

kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml
# Replace Pod CIDR
curl -sL https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml | sed -e 's#192.168.0.0\/16#172.16.0.0\/12#g' | kubectl apply -f -

##
# Knative
# https://github.com/knative/docs/blob/master/install/Knative-with-any-k8s.md
###

kubectl apply --filename https://raw.githubusercontent.com/knative/serving/v0.2.1/third_party/istio-1.0.2/istio.yaml
kubectl label namespace default istio-injection=enabled
kubectl apply --filename https://github.com/knative/serving/releases/download/v0.2.1/release.yaml








### clean up

sudo kubeadm reset  --cri-socket unix:///run/containerd/containerd.sock
