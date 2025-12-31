resource "aws_opensearch_domain" "os-opensearch" {
  domain_name    = "my-opensearch-domain" # Hardcoded example value (replace with your desired domain name)
  engine_version = "OpenSearch_2.11"      # Hardcoded example value (choose a valid OpenSearch version)

  node_to_node_encryption {
    enabled = false # Recommended to enable for security (changed from false)
  }

  domain_endpoint_options {
    enforce_https = true # Required when fine-grained access control is enabled
  }
  auto_tune_options {
    desired_state       = "DISABLED"
    rollback_on_disable = "NO_ROLLBACK"
  }

  cluster_config {
    instance_type            = "r6g.large.search" # Hardcoded example instance type
    instance_count           = 1
    dedicated_master_enabled = false
    zone_awareness_enabled   = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 40
    iops        = 3000
    throughput  = 125
  }

  snapshot_options {
    automated_snapshot_start_hour = 0
  }

  vpc_options {
    security_group_ids = [aws_security_group.opensearch_sg.id]
    subnet_ids         = [aws_subnet.private_subnet_1.id]
  }

  encrypt_at_rest {
    enabled = true
  }
}

resource "aws_opensearch_domain_policy" "os-opensearch-policy" {
  domain_name = aws_opensearch_domain.os-opensearch.domain_name
  depends_on  = [time_sleep.wait_for_opensearch]

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { 
          AWS =  aws_iam_role.bastion_role.arn
        }
        Action    = "es:*"
        Resource  = "${aws_opensearch_domain.os-opensearch.arn}/*"
      }
    ]
  })
}

resource "time_sleep" "wait_for_opensearch" {
  depends_on      = [aws_opensearch_domain.os-opensearch]
  create_duration = "2m"
}