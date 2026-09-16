# K8S-On-AWS-With-TerraForm-Demo

*Provisions a Kubernetes cluster on AWS with Terraform and Bash, then runs a series of standalone demos on top of it — built for demonstration and proof-of-concept purposes.*

---

## Description

This repo takes a cluster from nothing to fully working, then uses it to demonstrate core Kubernetes concepts one at a time. It is split into four stages, run in order:

| # | Folder | What it does |
|---|---|---|
| 1 | [Build](./Build/README.md) | Terraform: provisions the AWS networking, bastion host, and bare Kubernetes nodes |
| 2 | [Install](./Install/README.md) | `install-k8s-node.sh`: bootstraps Kubernetes on each node with `kubeadm` |
| 3 | [Prep](./Prep/README.MD) | Installs the cluster-wide add-ons every demo depends on (storage class, ingress controller) |
| 4 | [Demo](./Demo/README.md) | Standalone demos, each focused on a single Kubernetes concept or object type |

---

## Intention of Use

This is for demonstration and proof-of-concept purposes only — not intended for production use.

**Do not use this in a production environment.**

---

Enjoy
