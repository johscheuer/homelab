# Develop Kubernetes features

## Cross complie specific component

```bash
./build/run.sh make kubelet KUBE_BUILD_PLATFORMS=linux/amd64
```

## Run kubbeadm with kubenet

Setup a node with [kubeadm] and edit the following file after running `kubeadm init ...`:

```bash
sudo vim /var/lib/kubelet/kubeadm-flags.env
# add --pod-cidr='172.16.0.0/16' --non-masquerade-cidr='172.16.0.0/16'
# Change: --network-plugin=cni to --network-plugin=kubenet
```

After the changes you need to restart the kubelet: `sudo systemctl restart kubelet`.
Allow scheduling on the master since we only have one node:

```bash
kubectl taint node joh-nuc node-role.kubernetes.io/master-
```

## Run specific tests

```bash
make test WHAT=./pkg/kubelet/dockershim/network/kubenet GOFLAGS=-v
```
