###################################################
###  This Module will create the Elastic IP(s)  ###
###           rquired for this lab              ###  
###################################################

#--------------------------------------------------


# Create NAT GW EIP
resource "aws_eip" "nat-gw-eip" {
  depends_on = [aws_internet_gateway.main-igw]

  tags = {
    Name       = "demo-eip-nat-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
  }
}


# Create LB EIP
resource "aws_eip" "lb-eip" {
  depends_on = [aws_internet_gateway.main-igw]

  tags = {
    Name       = "demo-eip-lb-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
  }
}

#========================================
