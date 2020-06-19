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

TBD

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

Kubernetes DualStack + Endpoint Slices -> https://www.linkedin.com/pulse/how-enable-ipv6-kubernetes-cluster-ahmed-el-fakharany/

## Cluster Setup

TBD

--> metallb + ingress
--> Prometheus
--> Dualstack
--> Storage rook.io (Ceph)
