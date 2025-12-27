##################################  VPC Resources  ##################################
data "aws_vpc" "default_vpc" {
  default = true
}

resource "aws_default_subnet" "default_subnet_1" {
  availability_zone = "ap-south-1a"
  tags = {
    Name = "default-subnet-1"
  }
}

resource "aws_default_subnet" "default_subnet_2" {
  availability_zone = "ap-south-1b"
  tags = {
    Name = "default-subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.48.0/20"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.64.0/20"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = data.aws_vpc.default_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

resource "aws_eip" "eip_nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "eip-nat-gateway"
  }
}

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

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

##################################  Security Groups  ##################################
resource "aws_security_group" "bastion_sg" {
  name_prefix = "bastion-sg-"
  vpc_id      = data.aws_vpc.default_vpc.id
  description = "Security group for Bastion EC2 instance"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "bastion-security-group"
  }
}

# Data source for current region
data "aws_region" "current" {}

# Data source for VPC Lattice managed prefix list (region-specific)
data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  name = "com.amazonaws.${data.aws_region.current.name}.vpc-lattice"
}

resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-sg-"
  vpc_id      = data.aws_vpc.default_vpc.id
  description = "Security group for ECS Fargate tasks"

  # Critical: Allow inbound from VPC Lattice managed prefix list (for client traffic AND health checks)
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
    description     = "Allow all traffic (including health checks) from VPC Lattice"
  }

  # Optional: Allow from Bastion for debugging
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow all TCP traffic from Bastion"
  }

  # Optional: Allow inter-task communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
    description = "Allow all traffic within security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "ecs-security-group"
  }
}

resource "aws_security_group" "vpc_lattice_sg" {
  name_prefix = "vpc-lattice-sg-"
  vpc_id      = data.aws_vpc.default_vpc.id
  description = "Security group for VPC Lattice service network association (controls client outbound to Lattice)"

  # This SG controls which resources in the VPC can act as clients to Lattice services
  # Allow outbound HTTPS to Lattice (if needed for client-side restrictions)
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
    description     = "Allow outbound to VPC Lattice"
  }

  # Inbound not strictly needed here, but keep for consistency or future use
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default_vpc.cidr_block]
    description = "Allow HTTPS for VPC Lattice from VPC (optional)"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow HTTPS from Bastion"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "vpc-lattice-security-group"
  }
}
##################################  Bastion EC2 Instance  ##################################
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_default_subnet.default_subnet_1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  associate_public_ip_address = true
  tags = {
    Name = "bastion-host"
  }
}

##################################  ECR Repositories  ##################################
resource "aws_ecr_repository" "service_a" {
  name                 = "fast-api-service-a-ecr"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "service-a-ecr-repository"
    Service = "service-a"
  }
}

resource "aws_ecr_repository" "service_b" {
  name                 = "fast-api-service-b-ecr"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "service-b-ecr-repository"
    Service = "service-b"
  }
}

##################################  AWS Private CA  ##################################
resource "aws_acmpca_certificate_authority" "lattice_pca" {
  type = "ROOT"
  
  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name  = "VPC Lattice Private CA"
      organization = "FastAPI Organization"
    }
  }

  usage_mode                      = "GENERAL_PURPOSE"
  permanent_deletion_time_in_days = 7

  tags = {
    Name = "vpc-lattice-ca"
  }
}

# Self-sign the Root CA certificate
resource "aws_acmpca_certificate" "root_ca_certificate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.lattice_pca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.lattice_pca.certificate_signing_request
  signing_algorithm           = "SHA256WITHRSA"
  
  validity {
    type  = "YEARS"
    value = 10
  }

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"
}

# Install the self-signed certificate to activate the CA
resource "aws_acmpca_certificate_authority_certificate" "root_ca_cert_install" {
  certificate_authority_arn = aws_acmpca_certificate_authority.lattice_pca.arn
  certificate               = aws_acmpca_certificate.root_ca_certificate.certificate
  certificate_chain         = aws_acmpca_certificate.root_ca_certificate.certificate_chain
}

##################################  ACM Private Certificates for Lattice Services  ##################################
resource "aws_acm_certificate" "service_a" {
  domain_name               = "service-a.fast-api.local"
  certificate_authority_arn = aws_acmpca_certificate_authority.lattice_pca.arn

  tags = {
    Name = "service-a-lattice-cert"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.root_ca_cert_install]
}

resource "aws_acm_certificate" "service_b" {
  domain_name               = "service-b.fast-api.local"
  certificate_authority_arn = aws_acmpca_certificate_authority.lattice_pca.arn

  tags = {
    Name = "service-b-lattice-cert"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.root_ca_cert_install]
}

##################################  CloudWatch Logs  ##################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/fast-api-vpc-lattice"
  retention_in_days = 7

  tags = {
    Name = "fast-api-ecs-logs"
  }
}

##################################  IAM Roles & Policies  ##################################
# Trust policy for ECS tasks
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Trust policy for ECS service (infrastructure role used for VPC Lattice)
data "aws_iam_policy_document" "ecs_infrastructure_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# ECS Infrastructure Role (required for VPC Lattice integration)
resource "aws_iam_role" "ecs_infrastructure_role" {
  name               = "fast-api-ecs-infrastructure-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_infrastructure_assume_role.json

  tags = {
    Name = "ecs-infrastructure-role"
  }
}

# Inline policy with exact permissions from AWS managed policy + additional for Fargate (ec2:DescribeNetworkInterfaces)
resource "aws_iam_role_policy" "ecs_infrastructure_vpc_lattice_policy" {
  name = "ecs-infrastructure-vpc-lattice-policy"
  role = aws_iam_role.ecs_infrastructure_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManagedVpcLatticeTargetRegistration"
        Effect = "Allow"
        Action = [
          "vpc-lattice:RegisterTargets",
          "vpc-lattice:DeregisterTargets"
        ]
        Resource = "arn:aws:vpc-lattice:*:*:targetgroup/*"
      },
      {
        Sid    = "DescribeVpcLatticeTargetGroup"
        Effect = "Allow"
        Action = "vpc-lattice:GetTargetGroup"
        Resource = "arn:aws:vpc-lattice:*:*:targetgroup/*"
      },
      {
        Sid    = "ListVpcLatticeTargets"
        Effect = "Allow"
        Action = "vpc-lattice:ListTargets"
        Resource = "arn:aws:vpc-lattice:*:*:targetgroup/*"
      },
      {
        Sid    = "DescribeEc2Resources"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces"  # Added for Fargate ENI/IP discovery
        ]
        Resource = "*"
      }
    ]
  })
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "fast-api-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (application permissions)
resource "aws_iam_role" "ecs_task_role" {
  name               = "fast-api-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "ecs-task-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

##################################  ECS Cluster  ##################################
resource "aws_ecs_cluster" "main" {
  name = "fast-api-vpc-lattice-cluster"

  tags = {
    Name = "fast-api-cluster"
  }
}

##################################  ECS Task Definitions  ##################################
resource "aws_ecs_task_definition" "service_a" {
  family                   = "fast-api-service-a"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "service-a"
      image = "${aws_ecr_repository.service_a.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8081
          protocol      = "tcp"
          name          = "service-a-port"
        }
      ]

      cpu       = 256
      memory    = 512
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "service-a"
        }
      }

      environment = [
        {
          name  = "SERVICE_NAME"
          value = "service-a"
        },
        {
          name  = "SERVER_PORT"
          value = "8081"
        },
        {
          name  = "SERVICE_B_LATTICE_ENDPOINT"
          value = "https://${aws_vpclattice_service.service_b.dns_entry[0].domain_name}"
        },
        {
          name  = "SERVICE_B_URL"
          value = "https://${aws_vpclattice_service.service_b.dns_entry[0].domain_name}/service-b/status"
        }
      ]
    }
  ])

  tags = {
    Name    = "service-a-task-definition"
    Service = "service-a"
  }
}

resource "aws_ecs_task_definition" "service_b" {
  family                   = "fast-api-service-b"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "service-b"
      image = "${aws_ecr_repository.service_b.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8082
          protocol      = "tcp"
          name          = "service-b-port"
        }
      ]

      cpu       = 256
      memory    = 512
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "service-b"
        }
      }

      environment = [
        {
          name  = "SERVICE_NAME"
          value = "service-b"
        },
        {
          name  = "SERVER_PORT"
          value = "8082"
        },
        {
          name  = "SERVICE_A_LATTICE_ENDPOINT"
          value = "https://${aws_vpclattice_service.service_a.dns_entry[0].domain_name}"
        },
        {
          name  = "SERVICE_A_URL"
          value = "https://${aws_vpclattice_service.service_a.dns_entry[0].domain_name}/service-a/status"
        }
      ]
    }
  ])

  tags = {
    Name    = "service-b-task-definition"
    Service = "service-b"
  }
}

##################################  VPC Lattice Service Network  ##################################
resource "aws_vpclattice_service_network" "main" {
  name      = "fast-api-service-network"
  auth_type = "NONE"

  tags = {
    Name = "fast-api-service-network"
  }
}

resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = data.aws_vpc.default_vpc.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [aws_security_group.vpc_lattice_sg.id]

  tags = {
    Name = "fast-api-vpc-association"
  }
}

##################################  VPC Lattice Services  ##################################
resource "aws_vpclattice_service" "service_a" {
  name               = "fast-api-service-a"
  auth_type          = "NONE"
  custom_domain_name = "service-a.fast-api.local"
  certificate_arn    = aws_acm_certificate.service_a.arn

  tags = {
    Name    = "service-a-lattice-service"
    Service = "service-a"
  }
}

resource "aws_vpclattice_service" "service_b" {
  name               = "fast-api-service-b"
  auth_type          = "NONE"
  custom_domain_name = "service-b.fast-api.local"
  certificate_arn    = aws_acm_certificate.service_b.arn

  tags = {
    Name    = "service-b-lattice-service"
    Service = "service-b"
  }
}

resource "aws_vpclattice_service_network_service_association" "service_a" {
  service_identifier         = aws_vpclattice_service.service_a.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = {
    Name    = "service-a-network-association"
    Service = "service-a"
  }
}

resource "aws_vpclattice_service_network_service_association" "service_b" {
  service_identifier         = aws_vpclattice_service.service_b.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = {
    Name    = "service-b-network-association"
    Service = "service-b"
  }
}

##################################  VPC Lattice Target Groups  ##################################
resource "aws_vpclattice_target_group" "service_a" {
  name = "fast-api-service-a-tg"
  type = "IP"

  config {
    port             = 8081
    protocol         = "HTTP"
    vpc_identifier   = data.aws_vpc.default_vpc.id
    protocol_version = "HTTP1"

    health_check {
      enabled                       = true
      path                          = "/service-a/status"
      protocol                      = "HTTP"
      port                          = 8081
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
    }
  }

  tags = {
    Name    = "service-a-target-group"
    Service = "service-a"
  }
}

resource "aws_vpclattice_target_group" "service_b" {
  name = "fast-api-service-b-tg"
  type = "IP"

  config {
    port             = 8082
    protocol         = "HTTP"
    vpc_identifier   = data.aws_vpc.default_vpc.id
    protocol_version = "HTTP1"

    health_check {
      enabled                       = true
      path                          = "/service-b/status"
      protocol                      = "HTTP"
      port                          = 8082
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
    }
  }

  tags = {
    Name    = "service-b-target-group"
    Service = "service-b"
  }
}

##################################  VPC Lattice Listeners  ##################################
resource "aws_vpclattice_listener" "service_a_https" {
  name               = "service-a-https-listener"
  protocol           = "HTTPS"
  service_identifier = aws_vpclattice_service.service_a.id
  port               = 443

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.service_a.id
        weight                  = 100
      }
    }
  }

  tags = {
    Name    = "service-a-https-listener"
    Service = "service-a"
  }
}

resource "aws_vpclattice_listener" "service_b_https" {
  name               = "service-b-https-listener"
  protocol           = "HTTPS"
  service_identifier = aws_vpclattice_service.service_b.id
  port               = 443

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.service_b.id
        weight                  = 100
      }
    }
  }

  tags = {
    Name    = "service-b-https-listener"
    Service = "service-b"
  }
}

##################################  ECS Services  ##################################
resource "aws_ecs_service" "service_a" {
  name            = "fast-api-service-a"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service_a.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg.id]
  }

  vpc_lattice_configurations {
    role_arn         = aws_iam_role.ecs_infrastructure_role.arn
    target_group_arn = aws_vpclattice_target_group.service_a.arn
    port_name        = "service-a-port"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_vpclattice_listener.service_a_https,
    aws_vpclattice_service_network_service_association.service_a,
    aws_iam_role_policy.ecs_infrastructure_vpc_lattice_policy
  ]

  tags = {
    Name    = "service-a-ecs-service"
    Service = "service-a"
  }
}

resource "aws_ecs_service" "service_b" {
  name            = "fast-api-service-b"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service_b.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg.id]
  }

  vpc_lattice_configurations {
    role_arn         = aws_iam_role.ecs_infrastructure_role.arn
    target_group_arn = aws_vpclattice_target_group.service_b.arn
    port_name        = "service-b-port"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_vpclattice_listener.service_b_https,
    aws_vpclattice_service_network_service_association.service_b,
    aws_iam_role_policy.ecs_infrastructure_vpc_lattice_policy
  ]

  tags = {
    Name    = "service-b-ecs-service"
    Service = "service-b"
  }

}##################################  Outputs  ##################################

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_connection_info" {
  description = "How to connect to bastion"
  value       = "Use EC2 Instance Connect from AWS Console to connect to instance: ${aws_instance.bastion.id}"
}

output "service_a_lattice_endpoint" {
  description = "Service A VPC Lattice endpoint"
  value       = "https://${aws_vpclattice_service.service_a.dns_entry[0].domain_name}"
}

output "service_b_lattice_endpoint" {
  description = "Service B VPC Lattice endpoint"
  value       = "https://${aws_vpclattice_service.service_b.dns_entry[0].domain_name}"
}
