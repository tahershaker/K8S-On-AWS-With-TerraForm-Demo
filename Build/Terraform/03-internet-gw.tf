#########################################################
###  This Module will create the Internet Gateway(s)  ###
###            rquired for this lab                   ###  
#########################################################

#--------------------------------------------------------

# Create the Internet Gateway resource
resource "aws_internet_gateway" "main-igw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name       = "demo-igw-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================
