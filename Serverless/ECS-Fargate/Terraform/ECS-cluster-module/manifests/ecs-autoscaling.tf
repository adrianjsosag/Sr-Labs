# >>> [EC2] disabled
# # AWS Auto Scaling Group Terraform Module
# # EC2 container instances of the ECS cluster, spread across the 3 private subnets
# module "autoscaling" {
#   source  = "terraform-aws-modules/autoscaling/aws"
#   version = "9.3.2"
#
#   name = "${local.cluster_name}-asg"
#
#   # Launch Template
#   image_id        = data.aws_ssm_parameter.ecs_optimized_ami.value
#   instance_type   = var.ecs_instance_type
#   key_name        = module.key_pair.key_pair_name
#   security_groups = [aws_security_group.ecs_instances.id, aws_security_group.ecs_ssh_access.id]
#
#   # Registers the instance in the ECS cluster when it boots
#   user_data = base64encode(<<-EOT
#     #!/bin/bash
#     cat <<'EOF' >> /etc/ecs/ecs.config
#     ECS_CLUSTER=${local.cluster_name}
#     ECS_ENABLE_TASK_IAM_ROLE=true
#     EOF
#   EOT
#   )
#
#   block_device_mappings = [
#     {
#       device_name = "/dev/xvda"
#       ebs = {
#         volume_size           = var.ecs_root_volume_size
#         volume_type           = "gp3"
#         encrypted             = true
#         delete_on_termination = true
#       }
#     }
#   ]
#
#   # IAM Instance Profile - allows the ECS agent to register and SSM Session Manager access
#   create_iam_instance_profile = true
#   iam_role_name               = "${local.cluster_name}-ec2"
#   iam_role_description        = "ECS container instance role for ${local.cluster_name}"
#   iam_role_policies = {
#     AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
#     AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   }
#
#   # Auto Scaling Group
#   vpc_zone_identifier = data.terraform_remote_state.vpc.outputs.private_subnets
#   health_check_type   = "EC2"
#   min_size            = var.ecs_asg_min_size
#   max_size            = var.ecs_asg_max_size
#   desired_capacity    = var.ecs_asg_desired_capacity
#
#   # Capacity is managed by the ECS capacity provider
#   ignore_desired_capacity_changes = true
#   protect_from_scale_in           = true
#   force_delete                    = true
#
#   autoscaling_group_tags = {
#     AmazonECSManaged = true
#   }
#
#   tags = local.common_tags
# }
# <<< [EC2]
