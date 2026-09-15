#######################################################
###  This file will include the aws data provider   ###  
###      to be used to locate the required info     ### 
#######################################################

#========================================================

# Get the Ubuntu AMI to use for the bastion and the Kube nodes
# var.ubuntu-ami-name controls the version - update it in variables.tf when you want to move
# to a different Ubuntu release (e.g. jammy 22.04 vs noble 24.04)
data "aws_ami" "ami-ubuntu" {
  most_recent = true
  owners      = [var.ubuntu-ami-owner]

  filter {
    name   = "name"
    values = [var.ubuntu-ami-name]
  }

  filter {
    name   = "virtualization-type"
    values = [var.ubuntu-ami-virtualization-type]
  }

  filter {
    name   = "architecture"
    values = [var.ubuntu-ami-architecture]
  }

  filter {
    name   = "root-device-type"
    values = [var.ubuntu-ami-root-device-type]
  }
}
