# >>> [EC2] disabled
# # AWS EC2 Security Groups for the ECS container instances (private subnets)
# # With Fargate each ECS service defines the Security Group of its tasks instead.
#
# # Security Group - ECS container instances: ECS dynamic ports from the VPC, egress all
# resource "aws_security_group" "ecs_instances" {
#   name        = "${local.cluster_name}-instances-sg"
#   description = "ECS container instances: ECS dynamic ports from the VPC, egress all"
#   vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
#   tags        = merge(local.common_tags, { Name = "${local.cluster_name}-instances-sg" })
# }
#
# # Ingress Rule - ECS dynamic host ports (bridge network mode) from inside the VPC
# resource "aws_vpc_security_group_ingress_rule" "ecs_dynamic_ports_from_vpc" {
#   security_group_id = aws_security_group.ecs_instances.id
#   description       = "ECS dynamic host ports from the VPC"
#   cidr_ipv4         = data.terraform_remote_state.vpc.outputs.vpc_cidr_block
#   ip_protocol       = "tcp"
#   from_port         = 32768
#   to_port           = 65535
# }
#
# # Egress Rule - all-all open (ECS registration, image pulls via NAT, SSM)
# resource "aws_vpc_security_group_egress_rule" "ecs_all" {
#   security_group_id = aws_security_group.ecs_instances.id
#   description       = "Allow all outbound IPv4 traffic"
#   cidr_ipv4         = "0.0.0.0/0"
#   ip_protocol       = "-1"
# }
#
# # Security Group - SSH administration access from the public subnets (where the Bastion Host lives)
# # Owned by this project so the cluster does not depend on the Bastion Host state
# resource "aws_security_group" "ecs_ssh_access" {
#   name        = "${local.cluster_name}-ssh-access-sg"
#   description = "SSH administration access to the ECS container instances from the public subnets"
#   vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
#   tags        = merge(local.common_tags, { Name = "${local.cluster_name}-ssh-access-sg" })
# }
#
# # Ingress Rule - SSH (22) from each public subnet CIDR block
# resource "aws_vpc_security_group_ingress_rule" "ecs_ssh_from_public_subnets" {
#   for_each          = toset(data.terraform_remote_state.vpc.outputs.public_subnets_cidr_blocks)
#   security_group_id = aws_security_group.ecs_ssh_access.id
#   description       = "SSH from public subnet ${each.value}"
#   cidr_ipv4         = each.value
#   ip_protocol       = "tcp"
#   from_port         = 22
#   to_port           = 22
# }
# <<< [EC2]
