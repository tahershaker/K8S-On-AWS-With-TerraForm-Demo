# Prep - K8S On AWS With TerraForm Demo

*Cluster-wide add-ons that every demo in this repo depends on — installed once, right after the cluster is built and bootstrapped.*

---

## Description

The `Terraform` and `install-k8s-node.sh` steps in this repo deliberately leave the cluster bare: networking, nodes, and `kubeadm` plus a CNI, nothing else. Every demo under `Demo/` needs two things the cluster doesn't have on its own — somewhere to put persistent storage, and a way to route external traffic in. Rather than each demo installing these itself, this `Prep` folder installs them once, and every demo assumes they're already there.

It is part of the [K8S-On-AWS-With-TerraForm-Demo](https://github.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo) repository, and sits between the [Install](../Install/README.md) step and the [Demo](../Demo/README.md) folder in the overall workflow.

---

## Intention of Use

This prep work is intended for a **demo or lab environment** running on this repo's own cluster. It makes the same simplicity trade-offs as the rest of the repo — a node-local storage provisioner rather than a real CSI driver, an ingress controller bound directly to host ports rather than a cloud load balancer integration.

**Do not use these settings as-is in a production environment.**

---

## Repository Workflow Overview

This is step 3 in the repo's overall workflow:

1. **Provision the infrastructure with Terraform** — see [Build](../Build/README.md).
2. **Bootstrap each node with `install-k8s-node.sh`** — see [Install](../Install/README.md).
3. **Run this Prep step once, from the bastion.** Installs the cluster-wide add-ons every demo depends on.
4. **Run whichever demo(s) you want** — see [Demo](../Demo/README.md). Each demo's own README assumes this Prep step is already done and does not repeat it.

---

## What Gets Deployed, and Why

**A default `StorageClass`.** There is no cloud-controller-manager and no EBS CSI driver on these EC2 nodes, so nothing can satisfy a `PersistentVolumeClaim` on its own — and several demos in this repo (Harbor's database and registry storage among them) need one. This installs [`local-path-provisioner`](https://github.com/rancher/local-path-provisioner) and sets it as the default `StorageClass`. It's the standard lightweight choice for a bare demo cluster; its limitation is that a `PersistentVolume` is bound to whichever node the pod first lands on, so it's demo-grade, not highly available.

**An NGINX ingress controller.** The Terraform's Network Load Balancer forwards ports 80 and 443 straight to the three node IPs as instance targets — it does not route to a Kubernetes `NodePort` range. That means whatever handles ingress traffic has to bind directly to ports 80/443 on the host itself. This installs `ingress-nginx` as a `DaemonSet` with `hostNetwork: true`, with a toleration so it also runs on the master — without it, the Load Balancer's health check against the master's target always shows unhealthy, which is harmless but untidy. Because it's a `DaemonSet`, it automatically covers however many nodes you end up with, even if you've changed the Terraform's node count from the default.

---

## Prerequisites

- The Terraform in this repo already applied, and `install-k8s-node.sh` already run on every node — see the [Install README](../Install/README.md).
- `kubectl` on the bastion already pointed at the cluster (Install README, Step 6).
- `helm` on the bastion. If it isn't already there:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get_helm.sh
  chmod +x get_helm.sh
  ./get_helm.sh
  ```

---

## How to Use

### Step 1 — Install a default StorageClass

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Confirm it's there and marked default (look for `(default)` next to `local-path`):

```bash
kubectl get storageclass
```

![storageclass](/Install/Image/storageclass.png)

### Step 2 — Install the NGINX ingress controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.kind=DaemonSet \
  --set controller.hostNetwork=true \
  --set controller.dnsPolicy=ClusterFirstWithHostNet \
  --set controller.service.type=ClusterIP \
  --set controller.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set controller.tolerations[0].operator=Exists \
  --set controller.tolerations[0].effect=NoSchedule
```

Confirm one pod is running per node, each bound to the host network:

```bash
kubectl get pods -n ingress-nginx -o wide
```

![ingress](/Install/Image/ingress.png)

### Step 3 — Confirm the Load Balancer can reach it

From outside the cluster (your own machine is fine — the Load Balancer is internet-facing):

```bash
curl -i http://<lb_public_eip_public_ip from your Terraform output>
```

A `404` from `nginx` is the expected response at this point — it confirms the Load Balancer is reaching the ingress controller. There's nothing behind it to route to yet; that's what each demo adds.

![curl-result](/Install/Image/curl-result.png)

---

## Notes and Limitations

- **This step is idempotent enough to re-run**, but isn't designed to be re-applied constantly — run it once after Install, then move on to the demos.
- **`local-path-provisioner` is node-local.** Anything stored via it is pinned to whichever node the pod first scheduled on. Losing that node loses that data — acceptable for a demo, not for anything that needs to survive a node replacement.
- **The master runs ingress-nginx too, via the toleration.** This is purely to keep the Load Balancer's target-group health checks clean across all three nodes; a real cluster would typically keep ingress off the control plane.
- **If you've changed the Terraform's node count or topology**, no changes are needed here — the `DaemonSet` picks up however many nodes exist automatically. Only the demos' own default IPs/hostnames (documented in their individual READMEs) assume the default 1-master, 2-worker topology.
