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
    vpc_id = aws_default_vpc.default_vpc.id
    cidr_block = var.private_subnet_1_cidr
    availability_zone = local.availability_zone_subnet_1
    map_public_ip_on_launch = false
    tags = {
      Name = "${var.organization}-${var.region}-private-subnet-1"
    }
}

# Creating the public subnet 1 for the region
resource "aws_subnet" "private_subnet_2" {
  vpc_id = aws_default_vpc.default_vpc.id
  cidr_block = var.private_subnet_2_cidr
  availability_zone = local.availability_zone_subnet_2
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
  count = var.existing_nat_gateway ? 0 : 1
  allocation_id = var.existing_nat_gateway_allocation_id ? var.nat_gateway_allocation_id : aws_eip.eip_nat_gateway[0].id
  subnet_id = aws_default_subnet.default_subnet_1.id
  tags = {
    Name = "${var.organization}-${var.region}-nat-gateway-1"
  }
}

# creating the private route table for the private subnet
resource "aws_route_table" "private_route_table_1" {
  vpc_id = aws_default_vpc.default_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = var.existing_nat_gateway ? var.nat_gateway_id : aws_nat_gateway.nat_gatway_1[0].id
  }
  tags = {
    Name = "${var.organization}-${var.region}-private-route-table-1"
  }
}

# Association of private subnet 1 with the private route table 1
resource "aws_route_table_association" "private_rt_with_private_subnet_1" {
  subnet_id = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table_1.id
}

# Association of private subnet 2 with the private route table 2
resource "aws_route_table_association" "private_rt_with_private_subnet_2" {
  subnet_id = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table_1.id
}