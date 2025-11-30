##################################  VPC-Resources  ##################################
# Fetch the default VPC
data "aws_vpc" "default_vpc" {
  default = true
}

# Create default subnet 1 (without cidr_block and vpc_id)
resource "aws_default_subnet" "default_subnet_1" {
  availability_zone = "ap-south-1a"

  tags = {
    Name = "default-subnet-1"
  }
}

# Create default subnet 2 (without cidr_block and vpc_id)
resource "aws_default_subnet" "default_subnet_2" {
  availability_zone = "ap-south-1b"

  tags = {
    Name = "default-subnet-2"
  }
}

# Create the first private subnet
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.48.0/20"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-1"
  }
}

# Create the second private subnet
resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.64.0/20"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-2"
  }
}

# Create the route table for the private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = data.aws_vpc.default_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

# Create an Elastic IP (EIP) for the NAT Gateway
resource "aws_eip" "eip_nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "eip-nat-gateway"
  }
}

# Create a NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip_nat_gateway.id
  subnet_id     = aws_default_subnet.default_subnet_1.id
  tags = {
    Name = "nat-gateway"
  }
}

resource "aws_route" "private_nat_gateway_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_route_table_association" "private_subnet_1_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}
############################## AWS-Security-Group ############################
# Security Groups
resource "aws_security_group" "lb-sg" {
  name_prefix = "alb-sg"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs-sg" {
  name_prefix = "ecs-sg"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port       = 8201
    to_port         = 8201
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  ingress {
    from_port       = 8202
    to_port         = 8202
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
############################### AWS-ECR #####################################
resource "aws_ecr_repository" "fast_api_a" {
  name                 = "fast-api-a-ecr-repository"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "fast_api_b" {
  name                 = "fast-api-b-ecr-repository"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
################################ ##########################################
# Self-signed Certificate for ALB
resource "tls_private_key" "self_signed" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  private_key_pem = tls_private_key.self_signed.private_key_pem

  subject {
    common_name  = "fast-api-namespace"
    organization = "Example Organization"
  }

  validity_period_hours = 168 # 7 days

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = ["fast-api-namespace", "*.fast-api-namespace"]
}

# Upload self-signed certificate to ACM
resource "aws_acm_certificate" "alb_acm_certficate" {
  private_key      = tls_private_key.self_signed.private_key_pem
  certificate_body = tls_self_signed_cert.self_signed.cert_pem

  tags = {
    Name = "self-signed-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}
# Create Load Balancer
resource "aws_alb" "load_balancer" {
  name               = "ecs-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_default_subnet.default_subnet_1.id, aws_default_subnet.default_subnet_2.id]
  security_groups    = [aws_security_group.lb-sg.id]

  enable_deletion_protection = false

  tags = {
    Name = "ecs-alb"
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_alb.load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb_acm_certficate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_end_tg.arn
  }
}

resource "aws_lb_listener" "lb_http_listener" {
  load_balancer_arn = aws_alb.load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Create target group for frontend (without health checks like your working setup)
resource "aws_lb_target_group" "front_end_tg" {
  name        = "fe-tg"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default_vpc.id

  tags = {
    Name = "frontend-target-group"
  }
}

# Create target group for service-a (with health checks)
resource "aws_lb_target_group" "service_a_tg" {
  name        = "service-a-tg"
  port        = 8201
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/service-a/status"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "service-a-target-group"
  }
}

# Create target group for service-b (with health checks)
resource "aws_lb_target_group" "service_b_tg" {
  name        = "service-b-tg"
  port        = 8202
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/service-b/status"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "service-b-target-group"
  }
}

# Listener Rules
resource "aws_lb_listener_rule" "service_a" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_tg.arn
  }

  condition {
    path_pattern {
      values = ["/service-a/*"]
    }
  }
}

resource "aws_lb_listener_rule" "service_b" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_tg.arn
  }

  condition {
    path_pattern {
      values = ["/service-b/*"]
    }
  }
}
############################## AWS-ECS-IAM-Role-Policy #############################
# IAM Assume Role Policy for ECS Tasks
data "aws_iam_policy_document" "ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Create IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

# List of policies to attach
locals {
  ecs_task_policies = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
    "arn:aws:iam::aws:policy/AWSBatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSESFullAccess",
    "arn:aws:iam::aws:policy/AWSCloudMapFullAccess",
    "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
  ]
}

# Attach all IAM policies to ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policies" {
  for_each   = toset(local.ecs_task_policies)
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}

################################ AWS-ECS-Express-Gateway ##########################
# IAM Assume Role Policy for Infrastructure Role (Express Gateway Services)
data "aws_iam_policy_document" "ecs_infrastructure_assume_role_policy" {
  statement {
    sid     = "AllowAccessInfrastructureForECSExpressServices"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# IAM Role for Infrastructure (Express Gateway Services)
resource "aws_iam_role" "ecs_infrastructure_role" {
  name               = "ecsInfrastructureRoleForExpressServices"
  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure_role_policy" {
  role       = aws_iam_role.ecs_infrastructure_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "fast-api-cluster"
}

################################ Service A ################################
# CloudWatch Log Group for Service A
resource "aws_cloudwatch_log_group" "service_a_logs" {
  name              = "/ecs/fast-api-service-a-logs"
  retention_in_days = 7
}

# ECS Express Gateway Service A
resource "aws_ecs_express_gateway_service" "service_a_api_ecs" {
  cluster                 = aws_ecs_cluster.ecs_cluster.name
  service_name            = "service-a-api"
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn
  infrastructure_role_arn = aws_iam_role.ecs_infrastructure_role.arn

  primary_container {
    image          = "${aws_ecr_repository.fast_api_a.repository_url}:latest"
    container_port = 8081

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.service_a_logs.name
      log_stream_prefix = "service-a"
    }
  }

  network_configuration {
    subnets         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_groups = [aws_security_group.ecs-sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policies,
    aws_iam_role_policy_attachment.ecs_infrastructure_role_policy
  ]

  tags = {
    Name        = "service-a-api"
    Environment = "production"
  }
}

################################ Service B ################################
# CloudWatch Log Group for Service B
resource "aws_cloudwatch_log_group" "service_b_logs" {
  name              = "/ecs/fast-api-service-b-logs"
  retention_in_days = 7
}

# ECS Express Gateway Service B
resource "aws_ecs_express_gateway_service" "service_b_api_ecs" {
  cluster                 = aws_ecs_cluster.ecs_cluster.name
  service_name            = "service-b-api"
  cpu                     = 256
  memory                  = 512
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn
  infrastructure_role_arn = aws_iam_role.ecs_infrastructure_role.arn

  primary_container {
    image          = "${aws_ecr_repository.fast_api_b.repository_url}:latest"
    container_port = 8082

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.service_b_logs.name
      log_stream_prefix = "service-b"
    }
  }

  network_configuration {
    subnets         = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_groups = [aws_security_group.ecs-sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policies,
    aws_iam_role_policy_attachment.ecs_infrastructure_role_policy
  ]

  tags = {
    Name        = "service-b-api"
    Environment = "production"
  }
}

