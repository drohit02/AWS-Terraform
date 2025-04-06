resource "aws_security_group" "SG-aurora-db-sg" {
  name   = "SG-aurora-db-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "aurora-subnet-group" {
  name       = "aurora-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_x.id, aws_subnet.private_subnet_y.id]
}

resource "aws_rds_cluster" "dev-aurora-rds-cluster" {
  cluster_identifier     = "dev-aurora-rds-cluster-db"
  engine                 = "aurora-postgresql"
  engine_version         = "15.10"
  database_name          = "testdatabase"
  master_username        = "your-desire-username"
  master_password        = "your-desire-password"
  db_subnet_group_name   = aws_db_subnet_group.aurora-subnet-group.name
  vpc_security_group_ids = [aws_security_group.SG-aurora-db-sg.id]
  skip_final_snapshot    = true

  tags = {
    tag = "aurora-cluster"
  }
}

resource "aws_rds_cluster_instance" "dev-aurora-rds-cluster-instance-1" {
  count               = 1
  identifier          = "dev-aurora-instance-${count.index}"
  cluster_identifier  = aws_rds_cluster.dev-aurora-rds-cluster.id
  instance_class      = "db.r5.large"
  engine              = "aurora-postgresql"
  publicly_accessible = false
}
###########################################################################
# Create an IAM role for the Lambda function
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the AWS managed policy for full Lambda access
resource "aws_iam_role_policy_attachment" "lambda_full_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
}

# Attach the AWS managed policy for VPC access
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach the AWS managed policy for EC2 full access (includes ENI management)
resource "aws_iam_role_policy_attachment" "ec2_full_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}
# Attach the AmazonRDSFullAccess managed policy
resource "aws_iam_role_policy_attachment" "rds_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  role       = aws_iam_role.lambda_exec_role.name
}

# Attach the AmazonRDSDataFullAccess managed policy
resource "aws_iam_role_policy_attachment" "rds_data_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess"
  role       = aws_iam_role.lambda_exec_role.name
}
# Attach the AWS managed policy for full ECR access
resource "aws_iam_role_policy_attachment" "ecr_full_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# Create the Lambda function using a Docker image
resource "aws_lambda_function" "docker_lambda" {
  function_name = "docker_lambda_function"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "your-image-uri" # Replace with your Docker image URI
  timeout       = 60

   environment {
    variables = {
      DB_HOST = "your-rds-endpoint"  # Example variable
      DB_USER = "username"
      DB_PASSWORD = "password"
      DB_NAME = "testdatabase"
    }
  }

  # VPC configuration
  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet_x.id, aws_subnet.private_subnet_y.id] # Replace with your private subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_full_access,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy_attachment.ec2_full_access
  ]
}

# Security group for the Lambda function
resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "Security group for Lambda function"
  vpc_id      = data.aws_vpc.default.id

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
}