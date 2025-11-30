# ============================================
# Complete Terraform Configuration for AWS Cognito
# ============================================

# Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.awsregion
}

# ============================================
# Variables
# ============================================

variable "organization" {
  type        = string
  description = "Organization name"
  default     = "devops"
}

variable "awsregion" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"
  default     = "test"
}

variable "root_console_url" {
  type        = string
  description = "Callback URL for the SPA application"
  default     = "http://localhost:3000"
}

# ============================================
# Local Variables
# ============================================

locals {
  project_development_group_definitions = {
    "FRONTENT_DEVELOPER" = "Responsible for developing the reusable UI component"
    "BACKEND_DEVELOPER"  = "Responsible for Scaleable-Solution"
    "DATABASE_DEVELOPER" = "Responsible Optimizing the result-set and data-retrieval"
    "DEVOPS_ENGINEER"    = "Responsible for Security,Infrastructure developement"
  }
}

# ============================================
# Cognito User Pool
# ============================================

resource "aws_cognito_user_pool" "cognito_user_pool_data" {
  name = "${var.organization}-${var.awsregion}-${var.environment}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  mfa_configuration = "OFF"

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false
  }

  lifecycle {
    ignore_changes = [schema]
  }

  tags = {
    Environment  = var.environment
    Organization = var.organization
    ManagedBy    = "Terraform"
  }
}

# ============================================
# Cognito Resource Server (for M2M)
# ============================================

resource "aws_cognito_resource_server" "m2m_resource_server" {
  identifier   = "${var.environment}-m2m-resource-server"
  name         = "${var.environment}-m2m-resource-server"
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id

  scope {
    scope_name        = "read"
    scope_description = "Read access"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access"
  }

  depends_on = [aws_cognito_user_pool.cognito_user_pool_data]
}

# ============================================
# Cognito User Pool Client - SPA (OIDC Client)
# ============================================

resource "aws_cognito_user_pool_client" "spa_app_client" {
  name         = "${var.environment}-spa-app-client"
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "phone"]

  callback_urls = ["${var.root_console_url}/callback"]
  logout_urls   = [var.root_console_url]

  supported_identity_providers = ["COGNITO"]
  generate_secret              = false

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 5

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  depends_on = [aws_cognito_user_pool.cognito_user_pool_data]
}

# ============================================
# Cognito User Pool Client - M2M (OIDC Backend)
# ============================================

resource "aws_cognito_user_pool_client" "machine_to_machine_app_client" {
  name         = "${var.environment}-m2m-app-client"
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]

  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.m2m_resource_server.identifier}/read"
  ]

  access_token_validity  = 60
  refresh_token_validity = 5
  id_token_validity      = 60

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]
  enable_token_revocation      = true

  depends_on = [aws_cognito_resource_server.m2m_resource_server]
}

# ============================================
# Cognito User Groups
# ============================================

resource "aws_cognito_user_group" "cognito_groups" {
  for_each     = local.project_development_group_definitions
  name         = each.key
  description  = each.value
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id

  depends_on = [aws_cognito_user_pool.cognito_user_pool_data]
}

# ============================================
# Cognito User Pool Domain
# ============================================

resource "aws_cognito_user_pool_domain" "cognito_user_pool_domain" {
  domain                = "${var.organization}-${var.environment}-secure-login-domain"
  user_pool_id          = aws_cognito_user_pool.cognito_user_pool_data.id
  managed_login_version = 2

  depends_on = [aws_cognito_user_pool.cognito_user_pool_data]
}

resource "aws_cognito_managed_login_branding" "spa_branding" {
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id
  client_id    = aws_cognito_user_pool_client.spa_app_client.id

  # Use Cognito default managed style (no images/CSS needed)
  use_cognito_provided_values = true

  depends_on = [
    aws_cognito_user_pool_domain.cognito_user_pool_domain,
    aws_cognito_user_pool_client.spa_app_client
  ]
}

resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.cognito_user_pool_data.id
  username     = "rohit@gmail.com" # Change this to your email

  attributes = {
    email          = "rohit@gmail.com" # Change this to your email
    email_verified = true
  }

  desired_delivery_mediums = ["EMAIL"]

  # Set a temporary password (user will need to change on first login)
  temporary_password = "TempPass123!"

  depends_on = [aws_cognito_user_pool.cognito_user_pool_data]
}

variable "create_cognito_user" {
  type = bool
  default = true
}

variable "cognito_user" {
  type = list(string)
  default = ["rd@gmail.com" ,"rohit@gmail.com"]
}

###################### Output #######################
output "lower_environment" {
  value = var.create_cognito_user
}
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.cognito_user_pool_data.id
  sensitive = true
}
output "cognito_user_list" {
  value = var.cognito_user
  sensitive = false
}

output "aws_region" {
  value = var.awsregion
}

output "cognito_admin_group" {
  value = keys(local.project_development_group_definitions)[0]
}