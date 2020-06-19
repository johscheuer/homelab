# Metrics Server

## Why using the Metrics Server

Replaces Heapster ToDo

## Setup Metrics Server (Quick Way)

(Quick setup) Clone the official repository:

```bash
git clone --branch v0.3.1 https://github.com/kubernetes-incubator/metrics-server
cd metrics-server
```

Add the following part to the `metrics-server-deployment.yaml` file under `eploy/1.8+` (this will skip verifying Kubelet CA certificates - not recommended for production!):

```yaml
      - name: metrics-server
        image: k8s.gcr.io/metrics-server-amd64:v0.3.1
        args:
        - --kubelet-insecure-tls
```
