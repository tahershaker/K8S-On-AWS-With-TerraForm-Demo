# Install - K8S On AWS With TerraForm Demo

*Interactive kubeadm bootstrap for a Kubernetes-on-AWS demo cluster — one script, one node at a time.*

## Description

`install-k8s-node.sh` is an interactive Bash script that bootstraps a single Linux node into a Kubernetes cluster using the official `kubeadm` installation method. It runs standalone on each node in turn — there is no orchestration between nodes and no SSH involved. The script asks a series of questions about the cluster you're building, validates the answers, prints a summary for confirmation, and then installs and configures everything needed for that node to join (or start) the cluster.

It is part of the [K8S-On-AWS-With-TerraForm-Demo](https://github.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo) repository, which provisions the underlying AWS infrastructure via Terraform. This script handles the node-level Kubernetes installation step that follows.

## Intention of Use

This script is intended to speed up the creation of a Kubernetes cluster in a **demo or lab environment**. It trades some of the safeguards a production tool would have (idempotency, non-interactive automation, credential management) for simplicity and transparency — every step is visible, and nothing happens without an explicit confirmation.

**Do not use this script in a production environment.**

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

## Prerequisites

- A node already provisioned and reachable (via the accompanying Terraform code or otherwise), running a supported OS: Ubuntu, Debian, RHEL, Rocky Linux, AlmaLinux, or CentOS.
- Outbound internet access from the node (to `pkgs.k8s.io`, `download.docker.com`, and — for Calico — `api.github.com` and `raw.githubusercontent.com`).
- Root access on the node (the script must be run as `root` or via `sudo`).
- For a 3-master cluster: the Load Balancer already provisioned, listening on TCP port 6443, and passed through without TLS termination.

## Cluster Build Order

Run this script once on **each** node, one at a time, in this order:

1. The **first master** node — this initializes the cluster and prints the `kubeadm join` command(s) you'll need for the next steps.
2. Any **additional master** nodes (3-master clusters only) — each needs the control-plane join command printed by the first master. This command's `--certificate-key` is only valid for **2 hours**; if that window has passed, it must be regenerated on the first master before a new master can join.
3. Any **worker** nodes — each needs the worker join command printed by the first master.

## How to Use

Download the script directly onto the node using `curl` or `wget`, make it executable, and run it as root.

### Using curl

```bash
curl -fsSL https://raw.githubusercontent.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo/main/Install/Scripts/install-k8s-node.sh -o install-k8s-node.sh
chmod +x install-k8s-node.sh
sudo ./install-k8s-node.sh
```

### Using wget

```bash
wget https://raw.githubusercontent.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo/main/Install/Scripts/install-k8s-node.sh
chmod +x install-k8s-node.sh
sudo ./install-k8s-node.sh
```

The script is fully interactive from this point — answer each question as prompted, and confirm the final summary before installation begins.

## Notes and Limitations

- **CIDR overlap is not checked.** The Pod CIDR, Service CIDR, and the underlying VPC/node subnet CIDR must not overlap with each other. An overlap will break networking after installation, and this script will not catch it — verify the ranges yourself before entering them.
- **Kubernetes version is not validated against what's actually available.** The script checks the format (`X.Y`) but not whether that minor version is published on `pkgs.k8s.io`. Double-check the version exists before entering it.
- **The join command is not automated between nodes.** Since each node runs the script independently, you are responsible for copying the `kubeadm join` command printed by the first master and pasting it in when running the script on the next node.
- **This script is not idempotent.** It is designed to be run once per node, on a freshly provisioned machine. Re-running it on a node that has already been configured is not supported and may produce unexpected results.