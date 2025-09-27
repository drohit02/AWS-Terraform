provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45" # Or latest stable v5.x
    }
  }

  required_version = ">= 1.11.4"
}

####################################### AWS-VPC ########################################

# Accessing the default vpc from the respective region
resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name = "Default-VPC"
  }
}

# Accessing the default subnet 1 from the respective region
resource "aws_default_subnet" "default_subnet_1" {
  availability_zone = local.availability_zone_subnet_1
  tags = {
    Name = "${var.organization}-${var.region}-default-subnet-1"
  }
}

# Accessing the default subnet 2 from the respective region
resource "aws_default_subnet" "default_subnet_2" {
  availability_zone = local.availability_zone_subnet_2
  tags = {
    Name = "${var.organization}-${var.region}-default-subnet-2"
  }
}

# Creating the public subnet 1 for the region
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_default_vpc.default_vpc.id
  cidr_block        = var.public_subnet_1_cidr
  availability_zone = local.availability_zone_subnet_1
  tags = {
    Name = "${var.organization}-${var.region}-public-subnet-1"
  }
}

# Creating the public subnet 1 for the region
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_default_vpc.default_vpc.id
  cidr_block        = var.public_subnet_2_cidr
  availability_zone = local.availability_zone_subnet_2
  tags = {
    Name = "${var.organization}-${var.region}-public-subnet-2"
  }
}

# Creating the public subnet 1 for the region
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_default_vpc.default_vpc.id
  cidr_block              = var.private_subnet_1_cidr
  availability_zone       = local.availability_zone_subnet_1
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.organization}-${var.region}-private-subnet-1"
  }
}

# Creating the public subnet 1 for the region
resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = aws_default_vpc.default_vpc.id
  cidr_block              = var.private_subnet_2_cidr
  availability_zone       = local.availability_zone_subnet_2
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.organization}-${var.region}-private-subnet-2"
  }
}

#creating the elastic ip for the nat gatway 1
resource "aws_eip" "eip_nat_gateway" {
  count = var.existing_nat_gateway ? 0 : 1
}

# creating the NAT Gateaway for the project
resource "aws_nat_gateway" "nat_gatway_1" {
  count         = var.existing_nat_gateway ? 0 : 1
  allocation_id = var.existing_nat_gateway_allocation_id ? var.nat_gateway_allocation_id : aws_eip.eip_nat_gateway[0].id
  subnet_id     = aws_default_subnet.default_subnet_1.id
  tags = {
    Name = "${var.organization}-${var.region}-nat-gateway-1"
  }
}

# creating the private route table for the private subnet
resource "aws_route_table" "private_route_table_1" {
  vpc_id = aws_default_vpc.default_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.existing_nat_gateway ? var.nat_gateway_id : aws_nat_gateway.nat_gatway_1[0].id
  }
  tags = {
    Name = "${var.organization}-${var.region}-private-route-table-1"
  }
}

# Association of private subnet 1 with the private route table 1
resource "aws_route_table_association" "private_rt_with_private_subnet_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table_1.id
}

# Association of private subnet 2 with the private route table 2
resource "aws_route_table_association" "private_rt_with_private_subnet_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table_1.id
}

####################################### Security-Groups #######################################

# Creating security group for the AWS-Batch service
resource "aws_security_group" "sg_for_batch_service" {
  vpc_id = aws_default_vpc.default_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG-${var.organization}-${var.environment}-${var.region}-batch-service"
    tag  = local.env_tag
  }
}

####################################### AWS-ECR #######################################

# Creating the ECR repository for the java microservice 
resource "aws_ecr_repository" "ecr_java_microservice_1_repository" {
  name                 = "${var.organization}-${var.environment}-${var.region}-ecr-java-microservice-1-repository"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = {
    tag = local.env_tag
  }
}

# Creating the ECR repository for the python microservice
resource "aws_ecr_repository" "ecr_python_microservice_1_repository" {
  name                 = "${var.organization}-${var.environment}-${var.region}-ecr-python-microservice-1-repository"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = {
    tag = local.env_tag
  }
}

####################################### AWS-Batch-Role&Policy #######################################

data "aws_iam_policy_document" "ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# creating Iam Role for ECS Task for batch service
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.environment}-ECS-TaskExecution-Role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ECS_TaskExecution_Role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ECS_TaskExecution_Role_Cache_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
}

resource "aws_iam_role_policy_attachment" "ECS_S3FullAccess_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ECS_SecretsManager_ReadWrite_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ECS_ECSFullAccess_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy_attachment" "ECS_Batch_FullAccess_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "ECS_SES_FullAccess_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "ECS_AWSCloudMap_FullAccess_Policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
}

# Creating IAM Role for AWS Batch Service
resource "aws_iam_role" "batch_service_role" {
  name = "${var.organization}-${var.environment}-${var.region}-batch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    "Environment" = local.env_tag
  }
}

# Attach the AWS managed policy to the Batch service role
resource "aws_iam_role_policy_attachment" "batch_service_role_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
  depends_on = [aws_iam_role.batch_service_role]
}
resource "aws_iam_role_policy_attachment" "ecs_full_access_policy_attachment" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  depends_on = [aws_iam_role.batch_service_role]
}

# Creating the IAM Role for EC2 Instances in Batch Compute Environment
resource "aws_iam_role" "batch_instance_role" {
  name = "${var.organization}-${var.environment}-${var.region}-batch-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach required policies to EC2 instance role for batch
resource "aws_iam_role_policy_attachment" "batch_instance_role_policy_ec2" {
  role       = aws_iam_role.batch_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Instance Profile for EC2 Instances in Batch
resource "aws_iam_instance_profile" "batch_instance_profile" {
  name = "${var.organization}-${var.environment}-${var.region}-batch-instance-profile"
  role = aws_iam_role.batch_instance_role.name
}

#######################################  AWS-Batch #######################################

# Creating the cloudwatch log groups for the java micorservice batch 
resource "aws_cloudwatch_log_group" "cloudwatch_log_for_java_microservice_batch" {
  name = "/aws/batch/${var.organization}-${var.environment}-java-microservice-batch-logs"
  tags = {
    tag = local.env_tag
  }
}

# Creating the compute envrionement for the java microservice batch
resource "aws_batch_compute_environment" "java_microservice_batch_compute_environment" {
  name         = "${var.organization}-${var.environment}-java-microservice-batch-compute-env"
  type         = "MANAGED"
  state        = "ENABLED"
  service_role = aws_iam_role.batch_service_role.arn
  depends_on   = [aws_iam_role_policy_attachment.ecs_full_access_policy_attachment]

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    min_vcpus           = 0
    max_vcpus           = 32
    desired_vcpus       = 0
    instance_type       = ["optimal"]
    subnets             = [aws_subnet.private_subnet_1.id]
    security_group_ids  = [aws_security_group.sg_for_batch_service.id]
    ec2_key_pair        = ""
    instance_role       = aws_iam_instance_profile.batch_instance_profile.arn

    ec2_configuration {
      image_type = "ECS_AL2"
    }
  }

  tags = {
    tag = local.env_tag
  }
}

# Creating the Job Queue for the Java-Microservice batch
resource "aws_batch_job_queue" "java_microservice_job_queue" {
  name       = "${var.organization}-${var.environment}-java-microservice-job-queue"
  state      = "ENABLED"
  priority   = 0
  depends_on = [aws_batch_compute_environment.java_microservice_batch_compute_environment]

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.java_microservice_batch_compute_environment.arn
  }
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    tag = local.env_tag
  }
}

# Creating the Job definition for the java microservice batch
resource "aws_batch_job_definition" "java_microservice_job_definition" {
  name = "${var.organization}-${var.environment}-java-microservice-batch-job-definition"
  type = "container"

  container_properties = jsonencode({
    #image           = "${aws_ecr_repository.ecr_java_microservice_1_repository.repository_url}"
    image           = "amazonlinux"
    command         = ["echo", "java aws batch running"]
    volumes         = []
    jobRoleArn      = "${aws_iam_role.ecs_task_execution_role.arn}"
    excutionRoleArn = "${aws_iam_role.ecs_task_execution_role.arn}"
    environment = [
      { name = "CONNECTION", value = "${var.environment}" },
      { name = "URL", value = "www.google.com" },
    ]
    mountPoints = []
    ulimits     = []
    resourceRequirements = [
      { value = "2", type = "VCPU" },
      { value = "4096", type = "MEMORY" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "${aws_cloudwatch_log_group.cloudwatch_log_for_java_microservice_batch.name}"
        "awslogs-region"        = "${var.aws_region}"
        "awslogs-stream-prefix" = "${var.organization}-${var.environment}-java-microservice-batch"
      }
    }
  })
}

# CloudWatch Log Group for Python Microservice
resource "aws_cloudwatch_log_group" "cloudwatch_log_for_python_microservice_batch" {
  name = "/aws/batch/${var.organization}-${var.environment}-python-microservice-batch-logs"

  tags = {
    tag = local.env_tag
  }
}

# Compute Environment for Python Microservice
resource "aws_batch_compute_environment" "python_microservice_batch_compute_environment" {
  name         = "${var.organization}-${var.environment}-python-microservice-batch-compute-env"
  type         = "MANAGED"
  state        = "ENABLED"
  service_role = aws_iam_role.batch_service_role.arn
  depends_on   = [aws_iam_role_policy_attachment.ecs_full_access_policy_attachment]
  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    min_vcpus           = 0
    max_vcpus           = 32
    desired_vcpus       = 0
    instance_type       = ["optimal"]
    subnets             = [aws_subnet.private_subnet_1.id]
    security_group_ids  = [aws_security_group.sg_for_batch_service.id]
    ec2_key_pair        = ""
    instance_role       = aws_iam_instance_profile.batch_instance_profile.arn

    ec2_configuration {
      image_type = "ECS_AL2"
    }
  }

  tags = {
    tag = local.env_tag
  }
}

# Job Queue for Python Microservice
resource "aws_batch_job_queue" "python_microservice_job_queue" {
  name       = "${var.organization}-${var.environment}-python-microservice-job-queue"
  state      = "ENABLED"
  priority   = 1
  depends_on = [aws_batch_compute_environment.python_microservice_batch_compute_environment]

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.python_microservice_batch_compute_environment.arn
  }

  tags = {
    tag = local.env_tag
  }
}

# Multinode Job Definition for Python Microservice
resource "aws_batch_job_definition" "python_microservice_job_definition" {
  name = "${var.organization}-${var.environment}-python-microservice-batch-job-definition"
  type = "multinode"

  node_properties = jsonencode({
    numNodes = 1
    mainNode = 0

    nodeRangeProperties = [
      {
        targetNodes = "0"
        container = {
          #image            = "${aws_ecr_repository.ecr_python_microservice_1_repository.repository_url}"
          image            = "amazonlinux"
          command          = ["echo", "running aws batch"]
          jobRoleArn       = "${aws_iam_role.ecs_task_execution_role.arn}"
          executionRoleArn = "${aws_iam_role.ecs_task_execution_role.arn}"
          environment = [
            { name = "ENV", value = "${var.environment}" },
            { name = "LOG_LEVEL", value = "INFO" }
          ]
          resourceRequirements = [
            { value = "8", type = "VCPU" },
            { value = "16384", type = "MEMORY" }
          ]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "${aws_cloudwatch_log_group.cloudwatch_log_for_python_microservice_batch.name}"
              "awslogs-region"        = "${var.aws_region}"
              "awslogs-stream-prefix" = "${var.organization}-${var.environment}-python-microservice-batch"
            }
          }
        }
      }
    ]
  })
}
