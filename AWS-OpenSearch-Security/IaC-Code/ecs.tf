# ECR Repository for the FastAPI service
resource "aws_ecr_repository" "fastapi_service_a" {
  name         = "fastapi-service-a-repository"
  force_delete = true # Allows Terraform to delete the repo even if it contains images

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Private DNS Namespace for service discovery (internal to your VPC)
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "fast-api.internal" # e.g., fastapi.internal.local
  description = "Private DNS namespace for ECS service discovery"
  vpc         = data.aws_vpc.default_vpc.id # Replace with your VPC ID reference (e.g., aws_vpc.main.id)
}

# Cloud Map Service for the FastAPI service
resource "aws_service_discovery_service" "fastapi_discovery" {
  name = "fastapi-service-a" # This will be the DNS name: fastapi-service-a.internal.local

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 60
      type = "A" # A records for Fargate awsvpc mode (direct IP resolution)
    }

    routing_policy = "MULTIVALUE" # Returns up to 10 healthy endpoints
  }

}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "fast-api-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}
# Attach required managed policies (hardcoded ARNs)
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
    "arn:aws:iam::aws:policy/AWSBatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSESFullAccess",
    "arn:aws:iam::aws:policy/AWSCloudMapFullAccess",
    "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
  ])

  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}

# Inline policy for restricted OpenSearch access using specific HTTP methods
resource "aws_iam_role_policy" "ecs_opensearch_inline" {
  name = "fast-api-ecs-opensearch-inline"
  role = aws_iam_role.ecs_task_execution_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OpenSearchRestrictedMethods"
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "es:ESHttpHead" # Added HEAD as it's commonly required for health checks and existence queries
        ]
        Resource = "${aws_opensearch_domain.os-opensearch.arn}/*"
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "fastapi_cluster" {
  name = "fastapi-cluster"
}

resource "aws_ecs_task_definition" "fastapi_task" {
  family                   = "fastapi-service-a"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn # Same role as before

  container_definitions = jsonencode([
    {
      name      = "fastapi-container"
      image     = "${aws_ecr_repository.fastapi_service_a.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "OPENSEARCH_ENDPOINT"
          value = aws_opensearch_domain.os-opensearch.endpoint # e.g., my-opensearch-domain.us-east-1.es.amazonaws.com
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/fastapi-service-a"
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECS Service (example in private subnet with ALB - adjust as needed)
resource "aws_ecs_service" "fastapi_service" {
  name            = "fastapi-service-a"
  cluster         = aws_ecs_cluster.fastapi_cluster.id
  task_definition = aws_ecs_task_definition.fastapi_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id] # Use your private subnet
    security_groups  = [aws_security_group.ecs_sg.id]   # Create this SG to allow inbound from ALB
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.fastapi_discovery.arn
  }
  depends_on = [aws_service_discovery_service.fastapi_discovery]
}

# CloudWatch Log Group (created automatically, but explicit for clarity)
resource "aws_cloudwatch_log_group" "fastapi_logs" {
  name = "/ecs/fastapi-service-a"
}