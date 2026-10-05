# Create a terraform_data resource and Provisioners
resource "terraform_data" "copy_ec2_keys" {
  depends_on = [module.ec2_public, aws_eip.bastion_eip]
  # Re-run the provisioners if the Bastion Host is replaced
  triggers_replace = [module.ec2_public.id]

  # Connection Block for Provisioners to connect to EC2 Instance (uses the key created in ec2bastion-keypair.tf)
  connection {
    type        = "ssh"
    host        = aws_eip.bastion_eip.public_ip
    user        = "ec2-user"
    private_key = module.key_pair.private_key_openssh
  }

  ## File Provisioner: Copies the private key to /tmp/<bastion_name>.pem on the Bastion Host
  provisioner "file" {
    content     = module.key_pair.private_key_openssh
    destination = "/tmp/${module.key_pair.key_pair_name}.pem"
  }
  ## Remote Exec Provisioner: Using remote-exec provisioner fix the private key permissions on Bastion Host
  provisioner "remote-exec" {
    inline = [
      "sudo chmod 400 /tmp/${module.key_pair.key_pair_name}.pem"
    ]
  }
  ## Local Exec Provisioner: local-exec provisioner (Creation-Time Provisioner - Triggered during Create Resource)
  provisioner "local-exec" {
    command = "mkdir -p local-exec-output-files && echo Bastion Host created on `date` in VPC ID: ${data.terraform_remote_state.vpc.outputs.vpc_id} >> local-exec-output-files/creation-time-vpc-id.txt"
  }
}
