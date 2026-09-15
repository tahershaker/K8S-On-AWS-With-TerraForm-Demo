#######################################################
###   This Module will create the EC2 Instance(s),  ###
###             Required for this lab               ###  
#######################################################

#------------------------------------------------------

# First create the SSH Key Pair localy and add it to AWS
#-------------------------------------------------------

# Create a random suffix so the key name is unique per deployment
resource "random_string" "ssh-key-random" {
  length  = 6
  special = false
  upper   = false
}

# Create an RSA Key Pair of size 4096 bits
resource "tls_private_key" "ssh-key-pair-local-01" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create the SSH Key on AWS
resource "aws_key_pair" "demo-ssh-key-pair-01" {
  depends_on = [tls_private_key.ssh-key-pair-local-01]
  key_name   = "${random_string.ssh-key-random.result}-demo-key"
  public_key = tls_private_key.ssh-key-pair-local-01.public_key_openssh
}

# Create a local file with the content of the SSH Key
resource "local_file" "demo-ssh-key-pair" {
  depends_on      = [tls_private_key.ssh-key-pair-local-01]
  content         = tls_private_key.ssh-key-pair-local-01.private_key_pem
  filename        = var.ssh-file-name
  file_permission = "0400"
}

#========================================

# Second create the EC2 Instance(s)
#-----------------------------------

# Create Bastion Host in Public Subnet
resource "aws_instance" "bastion-01" {
  depends_on                  = [aws_route_table.pub-rt-01, aws_key_pair.demo-ssh-key-pair-01]
  ami                         = data.aws_ami.ami-os.id
  instance_type               = var.bastion-node-size
  subnet_id                   = aws_subnet.pub-sub-01.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pub-sg-01.id]
  private_ip                  = var.bastion-ip-addr
  key_name                    = aws_key_pair.demo-ssh-key-pair-01.key_name

  # Copy the private key onto the bastion so it can be used to jump to the private Kube nodes
  provisioner "file" {
    content     = tls_private_key.ssh-key-pair-local-01.private_key_pem
    destination = var.ssh-file-name
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = ["chmod 400 ${var.ssh-file-name}"]
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  tags = {
    Name       = "demo-bastion-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create Kube Master Node in Private Subnet
resource "aws_instance" "kube-master-01" {
  depends_on             = [aws_route_table.priv-rt-01, aws_nat_gateway.main-natgw, aws_key_pair.demo-ssh-key-pair-01]
  ami                    = data.aws_ami.ami-os.id
  instance_type          = var.kube-master-node-size
  subnet_id              = aws_subnet.priv-sub-01.id
  vpc_security_group_ids = [aws_security_group.priv-sg-01.id]
  private_ip             = var.kube-master-01-ip-addr
  key_name               = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.kube-node-disk-size
    delete_on_termination = true
  }

  tags = {
    Name       = "demo-kube-master-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create Kube Worker Node 01 in Private Subnet
resource "aws_instance" "kube-worker-01" {
  depends_on             = [aws_route_table.priv-rt-01, aws_nat_gateway.main-natgw, aws_key_pair.demo-ssh-key-pair-01]
  ami                    = data.aws_ami.ami-os.id
  instance_type          = var.kube-worker-node-size
  subnet_id              = aws_subnet.priv-sub-01.id
  vpc_security_group_ids = [aws_security_group.priv-sg-01.id]
  private_ip             = var.kube-worker-01-ip-addr
  key_name               = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.kube-node-disk-size
    delete_on_termination = true
  }

  tags = {
    Name       = "demo-kube-worker-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create Kube Worker Node 02 in Private Subnet
resource "aws_instance" "kube-worker-02" {
  depends_on             = [aws_route_table.priv-rt-01, aws_nat_gateway.main-natgw, aws_key_pair.demo-ssh-key-pair-01]
  ami                    = data.aws_ami.ami-os.id
  instance_type          = var.kube-worker-node-size
  subnet_id              = aws_subnet.priv-sub-01.id
  vpc_security_group_ids = [aws_security_group.priv-sg-01.id]
  private_ip             = var.kube-worker-02-ip-addr
  key_name               = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.kube-node-disk-size
    delete_on_termination = true
  }

  tags = {
    Name       = "demo-kube-worker-02"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================
