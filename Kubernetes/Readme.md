# Kubernetes dev setup

We have the following dev setup:

| name | vCPU | RAM | root disk | data disk |
|:-:|:-:|---|---|---|
| master | 2 | 4GB | 20GB | - |
| worker-0 | 4 | 8GB | 20GB | 80GB |
| worker-1 | 4 | 8GB | 20GB | 80GB |
| worker-2 | 4 | 8GB | 20GB | 80GB |
| total | 14 | 28GB | 80GB | 240GB (320GB total with root) |

BaseOS will be Ubuntu focal (20.04) for all machines (maybe I change this later on to something different)

## Setup local route

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

### Storage (Longhorn)

For cluster storage we will use [longhorn](https://longhorn.io/):

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.0.2/deploy/longhorn.yaml
```

Set longhorn to be the default storage class:

```bash
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

In order to access the longhorn ui run the following command:

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8000:80
```

and go to [http://localhost:8000](http://localhost:8000).

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

Create the services for the Prometheus service monitor of the `kube-controller-manager` and the `kube-scheduler`:

```bash
# TODO we also need to expose the metrics
kubectl create -f ./prometheus/
```

Check the installation (this may take a short moment until metrics are gathered):

```bash
kubectl top nodes
```

Ingress will be setup later but we can already use:

- For Grafana: `kubectl -n monitoring port-forward svc/grafana 3000:3000`
- For Prometheus: `kubectl -n monitoring port-forward svc/prometheus-k8s 9090:9090`

Install the [node-problem-detector](https://github.com/kubernetes/node-problem-detector):

```bash
# TODO add toleration for master
# Review settings: https://github.com/kubernetes/node-problem-detector#usage
kubectl  apply -f ./npd/
```

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

- https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
- https://kubernetes.io/docs/reference/access-authn-authz/node/
- https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#noderestriction
- https://github.com/open-policy-agent/gatekeeper
- https://github.com/kubernetes/node-problem-detector#remedy-systems
