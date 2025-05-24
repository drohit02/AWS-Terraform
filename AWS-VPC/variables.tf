variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

#Below region is for small naming covention only and value it abstaction of aws_region variable(e.g us-east-2 --->ue2)
variable "region" {
  type    = string
  default = "as1"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "organization" {
  type    = string
  default = "devops"
}

locals {
  env_tag                    = "${var.organization}-${var.environment}"
  opensearch_domain_name     = "${var.organization}-${var.environment}-${var.region}-os"
  availability_zone_subnet_1 = "${var.aws_region}a"
  availability_zone_subnet_2 = "${var.aws_region}b"
}

variable "public_subnet_1_cidr" {
  type    = string
  default = "172.31.64.0/20"
}
variable "public_subnet_2_cidr" {
  type    = string
  default = "172.31.80.0/20"
}
variable "private_subnet_1_cidr" {
  type    = string
  default = "172.31.96.0/20"
}
variable "private_subnet_2_cidr" {
  type    = string
  default = "172.31.112.0/20"
}

variable "existing_nat_gateway" {
  type    = bool
  default = false
}
variable "existing_nat_gateway_allocation_id" {
  type    = bool
  default = false
}
variable "nat_gateway_allocation_id" {
  type        = string
  description = "ID of the existing NAT gateway allocation"
  default     = "eipalloc-0b3b3b3b3b3b3b3b3"
}
variable "nat_gateway_id" {
  type        = string
  description = "ID of the existing NAT gateway"
  default     = "nat-99d9hw92982892g"
}