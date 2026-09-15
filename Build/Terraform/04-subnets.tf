###################################################
###  This Module will create the VPC Subnet(s)  ###
###           rquired for this lab              ###  
###################################################

#--------------------------------------------------


# First create the public VPC subnet
#------------------------------------

# Create the public subnet resource
resource "aws_subnet" "pub-sub-01" {
  vpc_id                  = aws_vpc.main-vpc.id
  cidr_block              = var.pub-sub-01-cidr
  availability_zone       = "${var.aws-region}a"
  map_public_ip_on_launch = true

  tags = {
    Name       = "demo-public-subnet-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================

# Second create the private VPC subnet
#--------------------------------------

# Create the private subnet resource
resource "aws_subnet" "priv-sub-01" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = var.priv-sub-01-cidr
  availability_zone = "${var.aws-region}a"

  tags = {
    Name       = "demo-private-subnet-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================
