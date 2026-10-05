# >>> [EC2] disabled
# # Get the recommended ECS-optimized Amazon Linux 2023 AMI ID (includes Docker and the ECS agent)
# data "aws_ssm_parameter" "ecs_optimized_ami" {
#   name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
# }
# <<< [EC2]
