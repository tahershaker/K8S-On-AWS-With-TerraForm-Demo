# Install - K8S On AWS With TerraForm Demo

*Interactive kubeadm bootstrap for a Kubernetes-on-AWS demo cluster — one script, one node at a time.*

---

## Description

`install-k8s-node.sh` (available in the `Install/Scripts` folder of this repo) is an interactive Bash script that bootstraps a single Linux node into a Kubernetes cluster using the official `kubeadm` installation method. It runs standalone on each node in turn — there is no orchestration between nodes and no SSH involved from the script itself. The script asks a series of questions about the cluster you're building, validates the answers, prints a summary for confirmation, and then installs and configures everything needed for that node to join (or start) the cluster.

It is part of the [K8S-On-AWS-With-TerraForm-Demo](https://github.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo) repository, which provisions the underlying AWS infrastructure via Terraform. This script is the node-level installation step that runs after that infrastructure is up.

---

## Intention of Use

This script is intended to speed up the creation of a Kubernetes cluster in a **demo or lab environment**. It trades some of the safeguards a production tool would have (idempotency, non-interactive automation, credential management) for simplicity and transparency — every step is visible, and nothing happens without an explicit confirmation.

**Do not use this script in a production environment.**

---

## Repository Workflow Overview

This script is one step inside a larger, end-to-end workflow. The full path, from nothing to a working cluster you can manage, looks like this:

1. **Provision the infrastructure with Terraform.** This creates the AWS networking, the bastion host, and the Kubernetes nodes. By default, this repo's Terraform provisions **1 master node and 2 worker nodes**.
2. **SSH into the bastion host.** The bastion is the only host with a public entry point; all the Kubernetes nodes sit in private subnets and are reached only through it.
3. **From the bastion, SSH into each Kubernetes node in turn** and run `install-k8s-node.sh` on it, following the order described below.
4. **Once every node has been bootstrapped**, copy the cluster's `kubeconfig` from the master node back to the bastion host, and install `kubectl` on the bastion so it can manage the cluster directly.

> **If you've changed the Terraform to deploy a different topology** (a different number of masters or workers, or additional resources), adjust the steps below accordingly — the node count and order described here assume the default 1-master, 2-worker setup this repo ships with.

---

## What This Script Will Do

Run once per node, the script will:

1. Confirm the node is running as `root`.
2. Ask how many master nodes the cluster will have (1 or 3), whether this node is a master or a worker, and — for a 3-master cluster — whether this is the first master or one joining an existing cluster.
3. Collect the information needed for this node's role: the Load Balancer or master IP, a `kubeadm join` command (for any node that isn't the first master), the Kubernetes version, and — for the first master only — the CNI choice (Calico or Cilium) and the Pod/Service network CIDRs.
4. Detect the node's OS (Ubuntu/Debian or RHEL/Rocky/AlmaLinux/CentOS) and print a full summary of everything collected, asking for one final confirmation before making any changes.
5. Perform OS pre-flight preparation: disable swap, load required kernel modules, and apply the sysctl parameters `kubeadm` needs.
6. Install and configure `containerd` as the container runtime.
7. Install `kubelet`, `kubeadm`, and (on master nodes) `kubectl` from the official Kubernetes package repository, pinned to the minor version you specified.
8. Either initialize the cluster with `kubeadm init` (first master only) or join the node to the existing cluster with `kubeadm join`, using the join command you provided.
9. On master nodes: configure `kubeconfig` for immediate use and for any future login session, and install Helm.
10. On the first master only: install the chosen CNI (Calico via the Tigera operator, or Cilium via Helm), configured to match the Pod CIDR you provided.
11. Print a final summary, and — on the first master — reprint the `kubeadm join` command(s) for the nodes still to be set up.

---

## Prerequisites

- The Terraform in this repo already applied, with the bastion host and Kubernetes nodes up and running.
- SSH access to the bastion host, and from the bastion onward to each Kubernetes node.
- Outbound internet access from each Kubernetes node (to `pkgs.k8s.io`, `download.docker.com`, and — for Calico — `api.github.com` and `raw.githubusercontent.com`).
- Root access on each node (the script must be run as `root` or via `sudo`).
- [Optional - If you have changed the Terraform and provisioned 3 master nodes] the Load Balancer already provisioned, listening on TCP port 6443, and passed through without TLS termination.

---

## Cluster Build Order

With this repo's default topology (1 master, 2 workers), SSH from the bastion into each node in turn and run the script in this order:

1. **The master node** — since there's only one master in the default topology, this is always the first master. It initializes the cluster and prints the `kubeadm join` command you'll need for the next two steps.
2. **Worker node 1** — needs the worker join command printed by the master.
3. **Worker node 2** — needs the same worker join command.

If you've changed the Terraform to deploy 3 masters instead of 1, the order becomes: first master, then the two additional masters (each needs the control-plane join command — note its `--certificate-key` is only valid for **2 hours**), then the worker nodes.

---

## How to Use

### Step 1 — Provision the infrastructure

Apply the Terraform in this repository to stand up the bastion host and the Kubernetes nodes, following the instructions in the repo's main README.

### Step 2 — SSH into the bastion host

```bash
ssh -i <path-to-your-key.pem> <bastion-user>@<bastion-public-ip>
```

### Step 3 — SSH from the bastion into a Kubernetes node

From the bastion, connect to the node you're about to bootstrap (start with the master node, per the build order above):

```bash
ssh -i <path-to-your-key.pem> <node-user>@<node-private-ip>
```

### Step 4 — Download and run the script on that node

```bash
curl -fsSL https://raw.githubusercontent.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo/main/Install/Scripts/install-k8s-node.sh -o install-k8s-node.sh
chmod +x install-k8s-node.sh
sudo ./install-k8s-node.sh
```

The script is fully interactive from this point — answer each question as prompted, and confirm the final summary before installation begins.

Repeat Steps 3 and 4 for every remaining node, in the order described above.

### Step 5 — Set up `kubectl` access from the bastion

Once every node has been bootstrapped, copy the cluster's `kubeconfig` from the master node to the bastion host, and install `kubectl` there so you can manage the cluster without SSHing further into the master each time.

From the bastion host:

```bash
# Copy the kubeconfig from the master node to the bastion
scp -i <path-to-your-key.pem> <node-user>@<master-node-private-ip>:/etc/kubernetes/admin.conf ~/.kube/config

# Make sure only you can read it
chmod 600 ~/.kube/config
```

Then install `kubectl` on the bastion itself (adjust for your bastion's OS):

**Debian/Ubuntu bastion:**
```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v<MAJOR.MINOR>/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v<MAJOR.MINOR>/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

**RHEL/Rocky/AlmaLinux bastion:**
```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v<MAJOR.MINOR>/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v<MAJOR.MINOR>/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
sudo dnf install -y kubectl --disableexcludes=kubernetes
```

Replace `<MAJOR.MINOR>` with the same Kubernetes minor version you entered when running the script (e.g. `1.31`).

Confirm it works:

```bash
kubectl get nodes
```

You should see all the nodes in the cluster, matching the topology you built.

---

## Notes and Limitations

- **This repo's default topology is 1 master and 2 workers.** The build order and step-by-step instructions above assume this default. If you've changed the Terraform to deploy a different number of nodes, or a 3-master setup, adjust the number of repetitions and the join-command handling accordingly.
- **CIDR overlap is not checked.** The Pod CIDR, Service CIDR, and the underlying VPC/node subnet CIDR must not overlap with each other. An overlap will break networking after installation, and this script will not catch it — verify the ranges yourself before entering them.
- **Kubernetes version is not validated against what's actually available.** The script checks the format (`X.Y`) but not whether that minor version is published on `pkgs.k8s.io`. Double-check the version exists before entering it.
- **The join command is not automated between nodes.** Since each node runs the script independently, you are responsible for copying the `kubeadm join` command printed by the master and pasting it in when running the script on each subsequent node.
- **This script is not idempotent.** It is designed to be run once per node, on a freshly provisioned machine. Re-running it on a node that has already been configured is not supported and may produce unexpected results.

---

## Script Output Example

The screenshot below shows the script running interactively on a node:

![script-output-example](/Install/image/script-output-example.png)

---
