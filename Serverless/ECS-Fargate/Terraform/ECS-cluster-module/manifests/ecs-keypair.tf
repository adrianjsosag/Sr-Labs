# >>> [EC2] disabled
# # AWS EC2 Key Pair Terraform Module
# # Generates a new private key (ED25519) for the ECS container instances and registers it in AWS
# # This Key Pair is different from the Bastion Host one: <cluster_name>-ec2
# module "key_pair" {
#   source  = "terraform-aws-modules/key-pair/aws"
#   version = "3.0.1"
#
#   key_name              = local.ec2_key_name
#   create_private_key    = true
#   private_key_algorithm = "ED25519"
#
#   tags = local.common_tags
# }
#
# # Save the private key locally in private-key/<cluster_name>-ec2.pem (read-only for the owner)
# resource "local_sensitive_file" "ec2_private_key" {
#   content         = module.key_pair.private_key_openssh
#   filename        = "${path.module}/private-key/${module.key_pair.key_pair_name}.pem"
#   file_permission = "0400"
# }
# <<< [EC2]
