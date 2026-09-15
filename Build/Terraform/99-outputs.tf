#######################################################
###     This Module will hold the values of the     ###
###    required output for the deployed resources   ###  
#######################################################

#------------------------------------------------------

output "bastion_public_ip" {
  value = aws_instance.bastion-01.public_ip
}

output "lb_public_eip_public_ip" {
  value = aws_eip.lb-eip.public_ip
}

output "ssh-key-name-aws" {
  value = aws_key_pair.demo-ssh-key-pair-01.key_name
}

output "kube-master-01-private-ip" {
  value = aws_instance.kube-master-01.private_ip
}

output "kube-worker-01-private-ip" {
  value = aws_instance.kube-worker-01.private_ip
}

output "kube-worker-02-private-ip" {
  value = aws_instance.kube-worker-02.private_ip
}

output "Deployment-Outputs" {
  value = <<EOF
  ========================================================
  Resource and information outputs for this deployement:
  ------------------------------------------------------
  - Bastion Host Public IP:                     ${aws_instance.bastion-01.public_ip}
  - Load Balancer Public IP:                    ${aws_eip.lb-eip.public_ip}
  - SSH Key Name:                               ${aws_key_pair.demo-ssh-key-pair-01.key_name}
  - Kube Master Node-01 Private IP:             ${aws_instance.kube-master-01.private_ip}
  - Kube Worker Node-01 Private IP:             ${aws_instance.kube-worker-01.private_ip}
  - Kube Worker Node-02 Private IP:             ${aws_instance.kube-worker-02.private_ip}
  ----------------------------------------------------------
  Next step: SSH to the bastion, then SSH from the bastion to each node
  using ${var.ssh-file-name} and run install-k8s-node.sh on each one.
  ----------------------------------------------------------
  EOF
}
