terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

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

# ECR Repositories
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

# AWS Private CA for Service Connect TLS
resource "aws_acmpca_certificate_authority" "pca_authority" {
  type = "ROOT"
  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name  = "Example Private CA"
      organization = "Example Org"
    }
  }

  usage_mode                      = "SHORT_LIVED_CERTIFICATE"
  permanent_deletion_time_in_days = 7

  tags = {
    Name             = "short-lived-ca"
    AmazonECSManaged = "true"
  }
}

# Get the CA certificate for the Private CA
resource "aws_acmpca_certificate" "ca_certificate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.pca_authority.arn
  certificate_signing_request = aws_acmpca_certificate_authority.pca_authority.certificate_signing_request
  signing_algorithm           = "SHA256WITHRSA"
  validity {
    type  = "DAYS"
    value = 15
  }

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"
}

# Install the certificate on the CA to make it active
resource "aws_acmpca_certificate_authority_certificate" "ca_cert_install" {
  certificate_authority_arn = aws_acmpca_certificate_authority.pca_authority.arn
  certificate               = aws_acmpca_certificate.ca_certificate.certificate
  certificate_chain         = aws_acmpca_certificate.ca_certificate.certificate_chain
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

# Service Discovery Private DNS Namespace
resource "aws_service_discovery_http_namespace" "fast_api_http_ns" {
  name        = "fast-api-namespace"
  description = "HTTP namespace for ECS Service Connect"
}

############################ ECS-Role-Policy-Permission ##################################  
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

# IAM Role for Service Connect TLS
resource "aws_iam_role" "ecs_service_connect_tls_role" {
  name = "service-connect-tls-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ecs.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
      }
    ]
  })
}

# IAM Policy for Service Connect TLS
resource "aws_iam_policy" "ecs_service_connect_tls_policy" {
  depends_on  = [aws_iam_role.ecs_service_connect_tls_role]
  name        = "service-connect-tls-policy"
  description = "Policy for ECS Service Connect TLS operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm-pca:GetCertificate",
          "acm-pca:IssueCertificate",
          "acm-pca:GetCertificateAuthorityCertificate",
          "acm-pca:DescribeCertificateAuthority"
        ]
        Resource = aws_acmpca_certificate_authority.pca_authority.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "ecs_service_connect_tls_policy_attachment" {
  depends_on = [aws_iam_policy.ecs_service_connect_tls_policy]
  role       = aws_iam_role.ecs_service_connect_tls_role.name
  policy_arn = aws_iam_policy.ecs_service_connect_tls_policy.arn
}

resource "aws_iam_role_policy_attachment" "ecs_service_connect_tls_managed_policy" {
  role       = aws_iam_role.ecs_service_connect_tls_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForServiceConnectTransportLayerSecurity"
}

resource "aws_iam_role_policy_attachment" "ecs_service_connect_service_discovery_full_access" {
  role       = aws_iam_role.ecs_service_connect_tls_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
}

resource "aws_iam_policy" "ecs_exec_policy" {
  name        = "ecs-exec-policy"
  description = "Allows ECS tasks to be accessed via ECS Exec (Session Manager)"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

################################ ECS-Service ########################################
# created ECS Cluster 
resource "aws_ecs_cluster" "ecs-cluster" {
  name = "fast-api-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.fast_api_http_ns.arn
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs.name
      }
    }
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/fast-api"
  retention_in_days = 7
}

# created ecs task definition for service-a
resource "aws_ecs_task_definition" "fargate-task-service-a" {
  family                   = "fargate-task-service-a"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "fargate-task-service-a"
      image = "${aws_ecr_repository.fast_api_a.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 8201
          name          = "service-a-port"
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      cpu      = 256
      memory   = 512
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
        }
      }

      environment = [
        { name = "SERVICE_NAME", value = "service-a" },
        { name = "SERVER_PORT", value = "8201" },
        { name = "SERVICE_B_URL", value = "http://service-b-sc:8202/service-b/status" }
      ]
    }
  ])
}

# created ecs task definition for service-b
resource "aws_ecs_task_definition" "fargate-task-service-b" {
  family                   = "fargate-task-service-b"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "fargate-task-service-b"
      image = "${aws_ecr_repository.fast_api_b.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 8202
          name          = "service-b-port"
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      cpu      = 256
      memory   = 512
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
        }
      }

      environment = [
        { name = "SERVICE_NAME", value = "service-b" },
        { name = "SERVER_PORT", value = "8202" },
        { name = "SERVICE_A_URL", value = "http://service-a-sc:8201/service-a/status" }
      ]
    }
  ])
}

# created service-a ECS service
resource "aws_ecs_service" "ecs_service_a" {
  name            = "ecs-service-a"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.fargate-task-service-a.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  enable_execute_command = true

  depends_on = [aws_alb.load_balancer, aws_lb_target_group.service_a_tg, aws_lb_listener_rule.service_a, aws_iam_role_policy_attachment.ecs_service_connect_tls_policy_attachment]

  lifecycle {
    ignore_changes = [desired_count]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service_a_tg.arn
    container_name   = aws_ecs_task_definition.fargate-task-service-a.family
    container_port   = 8201
  }

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs-sg.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.fast_api_http_ns.arn
    
    service {
      port_name      = "service-a-port"
      discovery_name = "service-a-sc"
      
      client_alias {
        port     = 8201
      }
      
      tls {
        role_arn = aws_iam_role.ecs_service_connect_tls_role.arn
        issuer_cert_authority {
          aws_pca_authority_arn = aws_acmpca_certificate_authority.pca_authority.arn
        }
      }
    }
  }
}

# created service-b ECS service
resource "aws_ecs_service" "ecs_service_b" {
  name            = "ecs-service-b"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.fargate-task-service-b.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  enable_execute_command = true

  depends_on = [aws_alb.load_balancer, aws_lb_target_group.service_b_tg, aws_lb_listener_rule.service_b, aws_iam_role_policy_attachment.ecs_service_connect_tls_policy_attachment]

  lifecycle {
    ignore_changes = [desired_count]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service_b_tg.arn
    container_name   = aws_ecs_task_definition.fargate-task-service-b.family
    container_port   = 8202
  }

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs-sg.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.fast_api_http_ns.arn
    
    service {
      port_name      = "service-b-port"
      discovery_name = "service-b-sc"
      
      client_alias {
        port     = 8202
      }
      
      tls {
        role_arn = aws_iam_role.ecs_service_connect_tls_role.arn
        issuer_cert_authority {
          aws_pca_authority_arn = aws_acmpca_certificate_authority.pca_authority.arn
        }
      }
    }
  }
}
