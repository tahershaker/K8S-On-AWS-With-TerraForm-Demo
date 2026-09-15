#######################################################
###   This file will hold all the variables used    ###
###           throughout this Terraform code        ### 
#######################################################

#------------------------------------------------------

# First Region and Networking variables
#---------------------------------------

variable "aws-region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "vpc-cidr" {
  description = "CIDR block for the main VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "pub-sub-01-cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.10.10.0/24"
}

variable "priv-sub-01-cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.10.20.0/24"
}

#========================================

# Second SSH Key variables
#--------------------------

variable "ssh-file-name" {
  description = "Local path to write the generated SSH private key to"
  type        = string
  default     = "demo-ssh-key.pem"
}

variable "ec2-user-name" {
  description = "Default SSH user for the Ubuntu AMI"
  type        = string
  default     = "ubuntu"
}

#========================================

# Third Bastion variables
#-------------------------

variable "bastion-ip-addr" {
  description = "Private IP to assign to the bastion host, inside the public subnet"
  type        = string
  default     = "10.10.10.11"
}

variable "bastion-node-size" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

#========================================

# Forth Kube Node variables
#---------------------------

variable "kube-master-01-ip-addr" {
  description = "Private IP for Kube Master Node-01"
  type        = string
  default     = "10.10.20.10"
}

variable "kube-worker-01-ip-addr" {
  description = "Private IP for Kube Worker Node-01"
  type        = string
  default     = "10.10.20.11"
}

variable "kube-worker-02-ip-addr" {
  description = "Private IP for Kube Worker Node-02"
  type        = string
  default     = "10.10.20.12"
}

variable "kube-master-node-size" {
  description = "EC2 instance type for the Kube master node"
  type        = string
  default     = "t3.medium"
}

variable "kube-worker-node-size" {
  description = "EC2 instance type for the Kube worker nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "kube-node-disk-size" {
  description = "Root volume size in GB for each Kube node"
  type        = number
  default     = 100
}

#========================================

# Fifth OS AMI variables
# Update os-ami-name to move between releases or distros (e.g. jammy 22.04 vs noble 24.04)
#-------------------------------------------------------------------------------------------

variable "os-ami-owner" {
  description = "AWS account ID that owns the AMI (099720109477 for official Canonical Ubuntu AMIs)"
  type        = string
  default     = "099720109477"
}

variable "os-ami-name" {
  description = "Name filter for the AMI lookup - set to the release you want, e.g. ubuntu-jammy-22.04 or ubuntu-noble-24.04"
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"
}

variable "os-ami-virtualization-type" {
  description = "Virtualization type filter for the AMI lookup"
  type        = string
  default     = "hvm"
}

variable "os-ami-architecture" {
  description = "Architecture filter for the AMI lookup"
  type        = string
  default     = "x86_64"
}

variable "os-ami-root-device-type" {
  description = "Root device type filter for the AMI lookup"
  type        = string
  default     = "ebs"
}

#========================================
