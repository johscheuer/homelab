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

## Setup local route

TODO docs

```bash
sudo route -n add -net 172.16.0.0/24 192.168.0.25
```

## Setup

Before we can start we need to setup the VM's:

```bash
pushd ./kubernetes-tf
terraform apply
```

Now we can take the output as input for the ansible inventory:

```bash
echo '[master]' > ../inventory/kube-dev
terraform output --json master_ip | jq -r '.[][] | select(startswith("172")) + " ansible_user=ubuntu"' >> ../inventory/kube-dev
echo '[worker]' >> ../inventory/kube-dev
terraform output --json worker_ips | jq -r '.[][] | select(startswith("172")) + " ansible_user=ubuntu"' >> ../inventory/kube-dev
# Set Kubernetes version from terraform
sed "s/K8S_VER/v$(terraform output --json kubernetes_version | jq -r '.')/g" ../playbook/vars/default.yml.tmp > ../playbook/vars/default.yml
popd
```

Check if all nodes are reachable:

```bas
ansible --ssh-common-args='-J jscheuermann@192.168.0.25' -i ./inventory/kube-dev all -m ping
```

Finally we can provision the Kubernetes cluster with [Ansible](https://docs.ansible.com):

```bash
ansible-playbook  --ssh-common-args='-J jscheuermann@192.168.0.25' -i ./inventory/kube-dev ./playbook/provision_kubeadm.yml
```

Connect to the master:

```bash
ssh -J jscheuermann@192.168.0.25 ubuntu@172.16.0.2
```

or work remotely with:

```bash
export KUBECONFIG="$(pwd)/playbook/kube.config/172.16.0.2/home/ubuntu/.kube/config"
```

## Networking

Host Networks:

- IPv4: `172.16.0.0/24`
- IPv6: `fd4a:fc40:8cfb::/64`

Service Networks (Kubernetes currently doesn't support `/64`):

- IPv4: `10.96.0.0/12`
- IPv6: `fd99:fe56:7891:2f3a::/112`

Pod Networks:

- IPv4: `192.168.0.0/16`
- IPv6: `fd44:fe56:7891:2f3a::/64`

We also activate endpoint slices for internal usage (kube-proxy).

## Cluster Setup

### Conformance Test

Install sonobouy for testing the conformance of the newly setup cluster:

```bash
curl -sLO https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.18.4/sonobuoy_0.18.4_linux_amd64.tar.gz
tar xfz sonobuoy_*
rm sonobuoy_*
sudo mv sonobuoy /usr/local/bin/
```

run the actual tests (more information can be found at [sonobouy](https://github.com/vmware-tanzu/sonobuoy#getting-started)):

```bash
sonobuoy run --wait
results=$(sonobuoy retrieve)
sonobuoy results $results
```

Clean up:

```bash
sonobuoy delete --wait
```

### Monitoring

The Prometheus setup is inspired by [kube-prometheus](https://github.com/coreos/kube-prometheus):

```bash
git clone -b release-0.6 https://github.com/coreos/kube-prometheus
cd kube-prometheus
kubectl create -f manifests/setup
sed -i 's/replicas: 3/replicas: 1/g' manifests/alertmanager-alertmanager.yaml
sed -i 's/replicas: 2/replicas: 1/g' ./manifests/prometheus-prometheus.yaml

kubectl create -f manifests/
```

Check the installation:

```bash
kubectl top nodes
```

Ingress will be setup later but we can already use `kubectl -n monitoring port-forward`.
We still need to fix the following two alerts: `KubeControllerManagerDown` and `KubeSchedulerDown`.
Just run `kubectl apply -f ./prometheus` to adjust the services.

Install the [node-problem-detector](https://github.com/kubernetes/node-problem-detector):

```bash
# TODO add toleration for master
# Review settings: https://github.com/kubernetes/node-problem-detector#usage
kubectl  apply -f ./npd/
```

### Storage (Rook)

For cluster storage we will use ceph deployed via rook:

```bash
kubectl create -f rook/common.yaml
kubectl create -f rook/operator.yaml
kubectl -n rook-ceph get pod
```

In the first place we create a default ceph cluster (later on we will customize it):

```bash
kubectl create -f rook/cluster.yaml
```

Deploy the rook [toolbox](https://rook.io/docs/rook/v1.4/ceph-toolbox.html):

```bash
# TODO
kubectl apply -f toolbox.yaml
```

and use the toolbox to verify the status of the cluster:

```bash
kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') -- bash
```

ensure that the cluster is in a good state:

```bash
ceph status
ceph osd status
ceph df
rados df
```

and now you can delete the toolbox:

```bash
kubectl delete -f toolbox.yaml
```

Setup Rook usage for Blockstorage:

```bash
# TODO move this file into the rook folder
# TODO use erasure coded?
cat << EOF | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: k8s-default
  namespace: rook-ceph
spec:
  failureDomain: host
  replicated:
    size: 3
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: rook-ceph-block
   annotations:
     storageclass.kubernetes.io/is-default-class: "true"
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
    clusterID: rook-cep
    pool: k8s-default
    imageFormat: "2"
    imageFeatures: layering
    # The secrets contain Ceph admin credentials.
    csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
    csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
    csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
    csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
    csi.storage.k8s.io/fstype: ext4
# Delete the rbd volume when a PVC is deleted
reclaimPolicy: Delete
EOF
# See also: kubectl create -f cluster/examples/kubernetes/ceph/csi/rbd/storageclass.yaml
```

--> TODO CephFS

### Metallb and ingress

--> metallb + ingress
--> LB Pool TBD -> 172.16.1.0/24 + fd77:fe56:7891:2f3a::/112

https://github.com/kubernetes-sigs/ip-masq-agent

### Logging

--> https://github.com/grafana/loki

## Testing

```bash
sudo ip6tables -vL KUBE-SERVICES
```

### Nodes

```bash
# https://kubernetes.io/docs/tasks/network/validate-dual-stack/system
kubectl get nodes master -o go-template --template='{{range .spec.podCIDRs}}{{printf "%s\n" .}}{{end}}'

kubectl get nodes master -o go-template --template='{{range .status.addresses}}{{printf "%s: %s \n" .type .address}}{{end}}'
```

### Communication

```bash
kubectl run  pod01 --image=busybox --command -- sleep 10000
kubectl run  pod02 --image=busybox --command -- sleep 10000
# Check networking
kubectl exec -it pod01 -- ip -o a s

kubectl exec -it pod02 -- ping6 -c 4 $ipv6
kubectl exec -it pod02 -- ping -c 4  $ipv4
```

### Multi tenancy

## Further ideas

-> https://metal-stack.io/
-> https://github.com/kubevirt/kubevirt
-> https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
-> https://kubernetes.io/docs/reference/access-authn-authz/node/
-> https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#noderestriction
-> https://github.com/open-policy-agent/gatekeeper
-> maybe replace rook?
-> https://github.com/rancher/system-upgrade-controller
-> https://github.com/oneinfra/oneinfra
-> https://github.com/kubernetes/node-problem-detector#remedy-systems
