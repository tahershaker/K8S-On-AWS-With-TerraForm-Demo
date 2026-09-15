# Terraform - K8S On AWS With TerraForm Demo

*Terraform-provisioned AWS infrastructure for a Kubernetes-on-AWS demo cluster — one VPC, one bastion, three bare nodes ready for manual bootstrap.*

---

## Description

This Terraform code (in the `Build/Terraform` folder of this repo) provisions the AWS infrastructure for a self-managed Kubernetes demo cluster: a VPC with a public and a private subnet, an Internet Gateway and NAT Gateway, security groups, an internet-facing Network Load Balancer, and four EC2 instances — a bastion host plus one Kubernetes master and two workers, all on Ubuntu.

It deliberately stops at infrastructure. The Kubernetes nodes are left bare on purpose — no `user_data`, no automated bootstrap. Once this Terraform has run, the [Install](../Install/README.md) section of this repo takes over: an interactive script (`install-k8s-node.sh`) you run by hand, one node at a time, over SSH through the bastion.

It is part of the [K8S-On-AWS-With-TerraForm-Demo](https://github.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo) repository. This is the infrastructure step; the node-level installation step is documented separately.

---

## Intention of Use

This Terraform is intended to stand up a **demo or lab environment** quickly and transparently. It trades some of the hardening a production environment would have — locked-down SSH access, high availability across multiple Availability Zones, a dynamic node count — for simplicity: everything is visible in a handful of numbered files, and nothing is hidden behind modules or automation you can't read top to bottom.

**Do not use this as-is in a production environment.** In particular, SSH to the bastion is open to `0.0.0.0/0` by default — see [Notes and Limitations](#notes-and-limitations) below.

---

## Repository Workflow Overview

This Terraform is the first step inside a larger, end-to-end workflow. The full path, from nothing to a working cluster you can manage, looks like this:

1. **Provision the infrastructure with this Terraform.** Creates the AWS networking, the bastion host, and the Kubernetes nodes. By default, it provisions **1 master node and 2 worker nodes**.
2. **SSH into the bastion host.** The bastion is the only host with a public entry point; all the Kubernetes nodes sit in a private subnet and are reached only through it.
3. **From the bastion, SSH into each Kubernetes node in turn** and run `install-k8s-node.sh` on it — see the [Install README](../Install/README.md) for the full step-by-step.
4. **Once every node has been bootstrapped**, copy the cluster's `kubeconfig` from the master node back to the bastion host, and install `kubectl` there.

This document covers step 1. Steps 2 through 4 are covered in full in the [Install README](../Install/README.md).

---

## What Gets Deployed

Running this Terraform creates, in order:

1. A VPC (`10.10.0.0/16` by default) with one public subnet and one private subnet, in a single Availability Zone.
2. An Internet Gateway attached to the VPC, and a NAT Gateway (with its own Elastic IP) sitting in the public subnet.
3. Two security groups — one for the public subnet (SSH, HTTP, HTTPS from the internet), one for the private subnet (all traffic from inside the VPC, and all traffic from the public security group).
4. Public and private route tables, with the public subnet routed to the Internet Gateway and the private subnet routed to the NAT Gateway.
5. An internet-facing Network Load Balancer, with target groups and listeners on ports 80 and 443, forwarding to all three Kubernetes nodes — for whichever node ends up running the ingress controller.
6. An RSA SSH key pair, generated fresh on every apply and written locally so you can connect to the bastion.
7. Four EC2 instances on Ubuntu: a bastion host in the public subnet, and one master plus two worker nodes in the private subnet — all left bare, with no Kubernetes software installed.

---

## Architecture Diagram

![architecture-diagram](/Build/Image/aws-arch.png)

---

## Prerequisites

- Terraform installed locally (`terraform -v` should return a version).
- AWS CLI installed and configured with credentials for an IAM user or role with sufficient permissions to create VPCs, EC2 instances, load balancers, and IAM-adjacent resources.
- No pre-existing SSH key needed — this Terraform generates its own key pair on apply.
- Outbound internet access to download the `aws`, `local`, `tls`, and `random` Terraform providers on `terraform init`.

---

## Repository Structure

| File | Purpose |
|---|---|
| `01-providers.tf` | Required providers and the AWS provider configuration |
| `02-vpc.tf` | The VPC |
| `03-internet-gw.tf` | Internet Gateway |
| `04-subnets.tf` | Public and private subnets |
| `05-eip.tf` | Elastic IPs for the NAT Gateway and the Load Balancer |
| `06-nat-gw.tf` | NAT Gateway |
| `07-security-groups.tf` | Security groups and their rules |
| `08-routing.tf` | Route tables and associations |
| `09-load-balancer.tf` | Network Load Balancer, target groups, and listeners |
| `10-compute.tf` | SSH key pair, bastion host, and the three Kubernetes nodes |
| `data.tf` | AMI lookup for the Ubuntu image used by all instances |
| `99-outputs.tf` | Output values printed after apply |
| `variables.tf` | All input variables and their defaults |

---

## Key Variables to Review Before Deploying

| Variable | Default | Why it matters |
|---|---|---|
| `aws-region` | `eu-west-1` | Where everything gets deployed |
| `vpc-cidr`, `pub-sub-01-cidr`, `priv-sub-01-cidr` | `10.10.0.0/16`, `10.10.10.0/24`, `10.10.20.0/24` | Network layout |
| `bastion-node-size`, `kube-master-node-size`, `kube-worker-node-size` | `t3.micro`, `t3.medium`, `t3.xlarge` | Instance sizing and cost |
| `kube-node-disk-size` | `100` (GB) | Root volume size for each Kubernetes node |
| `os-ami-name` | Ubuntu 26.04 wildcard pattern | Which Ubuntu release/build gets deployed |
| `ssh-file-name` | `./demo-ssh-key.pem` | Where the generated private key is written locally |

> **SSH is open to the internet by default** (`0.0.0.0/0` on port 22 to the bastion). See [Notes and Limitations](#notes-and-limitations).

---

## Customizing the Deployment

To change anything in this Terraform — network CIDRs, instance sizes, disk size, the OS/AMI, or anything else — edit `variables.tf` and any related object that depends on it. Changing a default in `variables.tf` is often enough on its own, but some changes (moving to a different OS family, changing the node topology) also touch the resource files directly — check the [Repository Structure](#repository-structure) table above for which file owns which resource.

### Changing the OS / AMI

The OS image used for the bastion and all three Kubernetes nodes is controlled by the `os-ami-*` variables in `variables.tf` (`os-ami-owner`, `os-ami-name`, `os-ami-virtualization-type`, `os-ami-architecture`, `os-ami-root-device-type`) — see `data.tf` for how these feed into the AMI lookup.

To move to a different OS, version, or AMI, first find the exact AMI you want in your target region. You can look it up with the AWS CLI:

```bash
aws ec2 describe-images \
  --region <your-region> \
  --image-ids <ami-id> \
  --query 'Images[0].{ID:ImageId,Name:Name,Owner:OwnerId,Description:Description,Arch:Architecture,Virt:VirtualizationType,RootDevice:RootDeviceType,State:State,Public:Public}' \
  --output table
```

This returns the AMI's name, owning account, architecture, virtualization type, and root device type — everything the `os-ami-*` variables need. Update each variable in `variables.tf` to match what this command returns, then run `terraform plan` to confirm the new AMI resolves correctly before applying.

Example output:

![aws-cli-ami-lookup](/Build/Image/aws-cli-ami-lookup.png)

![aws-cli-ami-lookup-output](/Build/Image/aws-cli-ami-lookup-output.png)

---

## A Note on Making Changes

This repo is intentionally simple and transparent rather than driven by a single central config, which means a change in one place can have effects elsewhere that Terraform itself won't catch or warn you about. If you change anything here — topology, IPs, OS, node count, sizing — you're responsible for checking whether that change needs to be reflected elsewhere in the repo too, most importantly in [`install-k8s-node.sh`](../Install/README.md) and its README, which assume this repo's default setup (1 master, 2 workers, Ubuntu, the specific IPs and hostnames documented there). A clean `terraform apply` does not mean the rest of the repo is still consistent with what you actually deployed.

---

## How to Use

### Step 1 — Clone the repo and move into the Terraform folder

```bash
git clone https://github.com/tahershaker/K8S-On-AWS-With-TerraForm-Demo.git
cd K8S-On-AWS-With-TerraForm-Demo/Build/Terraform
```

### Step 2 — Initialize Terraform

```bash
terraform init
```

### Step 3 — Validate the configuration

```bash
terraform validate
```

### Step 4 — Review the plan

```bash
terraform plan -out=tfplan
```

### Step 5 — Apply

```bash
terraform apply tfplan
```

### Step 6 — Note the outputs

After apply completes, Terraform prints the bastion's public IP, the Load Balancer's public IP, the SSH key name, and each node's private IP. You'll need these for the next step.

### Step 7 — Continue to node bootstrap

Move on to the [Install README](../Install/README.md) to SSH into the bastion and each node, and run `install-k8s-node.sh`.

---

## Outputs

| Output | Description |
|---|---|
| `bastion_public_ip` | Public IP to SSH into the bastion |
| `lb_public_eip_public_ip` | Public IP of the Network Load Balancer |
| `ssh-key-name-aws` | Name of the SSH key pair registered in AWS |
| `kube-master-01-private-ip` | Private IP of the master node |
| `kube-worker-01-private-ip` | Private IP of worker node 1 |
| `kube-worker-02-private-ip` | Private IP of worker node 2 |

---

## Cleanup

The NAT Gateway and the Network Load Balancer both bill hourly regardless of usage, plus data processing charges — they keep costing money even while the cluster sits idle. When you're done:

```bash
terraform destroy
```

---

## Notes and Limitations

- **SSH is open to `0.0.0.0/0` by default.** Port 22 on the bastion accepts connections from any IP on the internet. This is a deliberate simplification for this demo — lock it down to your own IP before deploying if that matters to you.
- **Single Availability Zone, no high availability.** Both subnets, the NAT Gateway, and all instances sit in one AZ. Losing that AZ takes down the whole cluster.
- **Fixed topology.** The node count (1 master, 2 workers) is hardcoded as individual resources, not driven by a variable — changing the count means editing `10-compute.tf` and `09-load-balancer.tf` directly, not just a variable value.
- **Nodes are left bare intentionally.** No `user_data`, no automated Kubernetes install — that's handled entirely by the manual, interactive process in the [Install README](../Install/README.md).
- **The Kubernetes nodes have no public IP.** The bastion is the only way in; the NAT Gateway is the only way out to the internet for the private nodes.

---

## Script Output Example

The screenshot below shows `terraform init` completing successfully, with all four providers (aws, random, local, tls) downloaded and the lock file created:

![terraform-output-example](/Build/Image/terraform-output-example.png)

The screenshot below shows `terraform apply` completing successfully — 40 resources added — with the full Deployment-Outputs block printed, including the bastion's public IP, the Load Balancer's public IP, the SSH key name, and each node's private IP:

![terraform-output-success](/Build/Image/terraform-output-success.png)