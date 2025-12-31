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

locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y unzip
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    aws --version > /var/log/awscli-version.log
    rm -rf /tmp/aws /tmp/awscliv2.zip
    echo "Setup completed at $(date)" >> /var/log/user-data.log
  EOF
}

resource "aws_instance" "bastion_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_default_subnet.default_subnet_1.id
  vpc_security_group_ids = [aws_security_group.bastion_ec2_sg.id]

  user_data                   = local.bastion_user_data
  user_data_replace_on_change = true
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  key_name                    = "ap-south-1-bastion-key-pair"
   metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  tags = { Name = "bastion-host" }
}

# IAM role for bastion - minimal permissions for OpenSearch access only
resource "aws_iam_role" "bastion_role" {
  name = "bastion-opensearch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "bastion-opensearch-role"
  }
}

# Minimal policy - only OpenSearch access, no CLI access needed
resource "aws_iam_role_policy" "bastion_opensearch_policy" {
  name = "bastion-opensearch-access"
  role = aws_iam_role.bastion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = [
          "es:*"
        ]
        Resource = "${aws_opensearch_domain.os-opensearch.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion-opensearch-profile"
  role = aws_iam_role.bastion_role.name
}
