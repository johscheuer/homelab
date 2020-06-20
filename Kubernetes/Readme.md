# Kubernetes dev setup

We have the following dev setup:

| name | vCPU | RAM | root disk | data disk |
|:-:|:-:|---|---|---|
| master | 2 | 4GB | 20GB | - |
| worker-0 | 2 | 8GB | 20GB | 80GB |
| worker-1 | 2 | 8GB | 20GB | 80GB |
| worker-2 | 2 | 8GB | 20GB | 80GB |
| total | 8 | 28GB | 80GB | 240GB (320GB total with root) |

BaseOS will be Ubuntu focal (20.04) for all machines (maybe I change this later on to something different)

## Setup

Before we can start we need to setup the VM's:

```bash
pushd ./kubernetes-tf
terraform apply
```

Now we can take the output as input for the ansible inventory:

```bash
# TODO test ansible with IPv6 and add groups
echo '[master]' > ../inventory/kube-dev
terraform output --json  master_ip | jq -r '.[][] | select(startswith("172")) + " ansible_user=ubuntu"' >> ../inventory/kube-dev
echo '[worker]' >> ../inventory/kube-dev
terraform output --json  worker_ips | jq -r '.[][] | select(startswith("172")) + " ansible_user=ubuntu"' >> ../inventory/kube-dev
popd
```

Check if all nodes are reachable:

```bas
ansible --ssh-common-args='-J jscheuermann@192.168.0.242' -i inventory/kube-dev all -m ping
```

Finally we can provision the Kubernetes cluster with [Ansible](https://docs.ansible.com):

```bash
TBD
```

## Networking

Host Networks:

- IPv4: `172.16.0.0/24`
- IPv6: `fd4a:fc40:8cfb::/64`

Service Networks:

-
-

Pod Networks:

-
-


## Cluster Setup

TBD -> setup with ansible (initial setup)

--> metallb + ingress
--> Prometheus
--> Dualstack
--> Storage rook.io (Ceph)

## Testing

```bash
sudo ip6tables -vL KUBE-SERVICES

```
