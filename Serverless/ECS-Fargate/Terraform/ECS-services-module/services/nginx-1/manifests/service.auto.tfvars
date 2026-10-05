# ECS Service: nginx-1 (test service)
# Published on http://<alb_dns_name>/nginx-1/ with its own page showing its name.
#
# Image from the private ECR (ECR-module). Push it BEFORE terraform plan/apply:
#   cd ../../../../ECR-module && ./push-image.sh nginx-1 1.0.0 --from public.ecr.aws/nginx/nginx:stable-alpine
service = {
  name                   = "nginx-1"
  ecr_repository         = "nginx-1" # repository of ECR-module (cloudengineering-stag/nginx-1)
  image_tag              = "1.0.0"   # immutable tag; deployed pinned by its digest
  launch_type            = "FARGATE" # FARGATE or EC2 (must match the ECS cluster mode)
  container_port         = 80
  cpu                    = 256 # 0.25 vCPU
  memory                 = 512 # 0.5 GB
  desired_count          = 2   # 2 tasks in different AZs
  autoscaling_max        = 4
  path_patterns          = ["/nginx-1", "/nginx-1/*"]
  listener_rule_priority = 110 # UNIQUE among all the services of the ALB
  health_check_path      = "/"

  # Creates /nginx-1/index.html with the service name and starts nginx
  command = [
    "/bin/sh", "-c",
    "mkdir -p /usr/share/nginx/html/nginx-1 && echo '<h1>nginx-1</h1><p>Servicio de prueba en Amazon ECS</p>' > /usr/share/nginx/html/nginx-1/index.html && exec nginx -g 'daemon off;'"
  ]
}
