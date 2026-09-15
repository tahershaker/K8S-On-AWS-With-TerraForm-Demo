################################################################
###  This Module will create the VPC(s) rquired for this lab ###  
################################################################

#---------------------------------------------------------------

# Create VPC(s)
#--------------

# Create the main VPC resource
resource "aws_vpc" "main-vpc" {
  cidr_block = var.vpc-cidr

  tags = {
    Name       = "demo-vpc-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
  }
}
