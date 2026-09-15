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
- A Docker daemon on the bastion, used as a client for registry operations in later demos. This is separate from `containerd`, which is what the cluster nodes actually use to run pods.
  ```bash
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo usermod -aG docker $USER
  newgrp docker
  ```
- The Load Balancer's public IP/FQDN, from the Terraform output.

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

---

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

![ingress](/Prep/Image/ingress.png)

---

### Step 3 — Confirm the Load Balancer can reach it

From outside the cluster (your own machine is fine — the Load Balancer is internet-facing):

```bash
curl -i http://<lb_public_eip_public_ip from your Terraform output>
```

A `404` from `nginx` is the expected response at this point — it confirms the Load Balancer is reaching the ingress controller. There's nothing behind it to route to yet; that's what each demo adds.

![curl-result](/Prep/Image/curl-result.png)

---

### Step 4 — Install Harbor

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update

helm install harbor harbor/harbor \
  --namespace harbor --create-namespace \
  --set expose.type=ingress \
  --set expose.ingress.className=nginx \
  --set expose.ingress.hosts.core=${HARBOR_HOST} \
  --set expose.tls.enabled=true \
  --set expose.tls.certSource=auto \
  --set externalURL=https://${HARBOR_HOST} \
  --set harborAdminPassword=${HARBOR_PASSWORD} \
  --set persistence.enabled=true
```

Harbor has several components (core, jobservice, registry, database, Redis, Trivy) and can take a few minutes to settle:

```bash
kubectl get pods -n harbor -w
```

---

### Step 5 — Trust Harbor's certificate on the bastion

`certSource=auto` makes the chart generate its own CA and TLS certificate as a Kubernetes Secret. Find it, then trust it locally so `docker login`/`push` work without `--insecure-registry`:

```bash
kubectl get secret -n harbor | grep ingress
# use the TLS secret name returned above in place of harbor-ingress below
kubectl get secret harbor-ingress -n harbor -o jsonpath='{.data.ca\.crt}' | base64 -d | sudo tee /usr/local/share/ca-certificates/harbor-ca.crt
sudo update-ca-certificates
sudo systemctl restart docker
```

---

### Step 6 — Trust the same certificate on every cluster node

This is easy to miss: once pods are pulling images from Harbor, it is `containerd` on each node — not Docker on the bastion — doing the TLS handshake. Skip this and every pod scheduled against a Harbor image fails with `ImagePullBackOff` on a certificate error.

From the bastion, for each node (default private IPs from the [Install README](../Install/README.md): master `10.10.20.10`, worker 1 `10.10.20.11`, worker 2 `10.10.20.12`):

```bash
for NODE_IP in 10.10.20.10 10.10.20.11 10.10.20.12; do
  scp -i <path-to-your-key.pem> /usr/local/share/ca-certificates/harbor-ca.crt <node-user>@${NODE_IP}:/tmp/harbor-ca.crt
  ssh -i <path-to-your-key.pem> <node-user>@${NODE_IP} \
    "sudo cp /tmp/harbor-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates && sudo systemctl restart containerd"
done
```

Restarting `containerd` briefly interrupts `kubectl logs`/`exec` connections to that node's pods, not the pods themselves — safe for a demo, worth timing outside anything you're actively demoing live.

### Step 7 — Confirm Harbor is reachable and log in

Browse to `https://${HARBOR_HOST}` (your browser will warn about the self-signed certificate — that's expected, proceed past it). Log in as `admin` / the password in `HARBOR_PASSWORD`.

Log the bastion's Docker client in too, ready for whichever demo needs to push images:

```bash
docker login ${HARBOR_HOST} -u admin -p ${HARBOR_PASSWORD}
```

Harbor is now ready. Each demo that needs it creates its own project inside it — see the individual demo's README.

---

## Notes and Limitations

- **This step is idempotent enough to re-run**, but isn't designed to be re-applied constantly — run it once after Install, then move on to the demos.
- **`local-path-provisioner` is node-local.** Anything stored via it — including Harbor's own database and registry storage — is pinned to whichever node the pod first scheduled on. Losing that node loses that data — acceptable for a demo, not for anything that needs to survive a node replacement.
- **The master runs ingress-nginx too, via the toleration.** This is purely to keep the Load Balancer's target-group health checks clean across all three nodes; a real cluster would typically keep ingress off the control plane.
- **Self-signed certificate.** Harbor's UI and every demo that exposes something through the same ingress will show a browser warning on first visit — expected for a demo, not something to fix here.
- **Plain-text admin password.** `harborAdminPassword` was set directly as a Helm value for simplicity. A real deployment would pre-create the Kubernetes Secret Harbor expects and reference it instead.
- **If you've changed the Terraform's node count or topology**, `local-path-provisioner` and `ingress-nginx` need no changes — they pick up however many nodes exist automatically. Only Step 6's node loop and the demos' own default IPs/hostnames assume the default 1-master, 2-worker topology.

---

## Next Action

Once the cluster-wide add-ons are installed and running, you are ready to start running demos on top of the cluster. Move on to the [Demo README](../Demo/README.md).

---

Enjoy
