# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1" # Ensure this is your preferred region
}

# Fetch the default VPC
data "aws_vpc" "default" {
  default = true
}

# Create Internet Gateway (since there is no IGW now)
resource "aws_internet_gateway" "igw" {
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "default-igw"
  }
}

# Create Public Subnets with non-overlapping CIDR blocks
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.1.0/24" # Adjusted CIDR block
  availability_zone       = "ap-south-1a"   # Ensure you are using valid AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "default-subnet-a"
  }
}

# Create two private subnets with the name "dev-lambda-private-subnet"
resource "aws_subnet" "dev_lambda_private_subnet_1" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.176.0/20"
  availability_zone = "ap-south-1a" # Change to your desired AZ
  tags = {
    Name = "dev-lambda-private-subnet-1"
  }
}

resource "aws_subnet" "dev_lambda_private_subnet_2" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.192.0/20"
  availability_zone = "ap-south-1b" # Change to your desired AZ
  tags = {
    Name = "dev-lambda-private-subnet-2"
  }
}

# Create an Elastic IP for the NAT Gateway
resource "aws_eip" "dev_lambda_nat_eip" {
  domain = "vpc"
  tags = {
    Name = "dev-lambda-nat-gateway-eip"
  }
}

# Create a NAT Gateway with the name "dev-lambda-nat-gateway" in the default public subnet
resource "aws_nat_gateway" "dev_lambda_nat_gateway" {
  allocation_id = aws_eip.dev_lambda_nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id # Use the default public subnet
  tags = {
    Name = "dev-lambda-nat-gateway"
  }
}

# Create a private route table for the private subnets
resource "aws_route_table" "dev_lambda_private_route_table" {
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "dev-lambda-private-route-table"
  }
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "dev_lambda_private_subnet_1_association" {
  subnet_id      = aws_subnet.dev_lambda_private_subnet_1.id
  route_table_id = aws_route_table.dev_lambda_private_route_table.id
}

resource "aws_route_table_association" "dev_lambda_private_subnet_2_association" {
  subnet_id      = aws_subnet.dev_lambda_private_subnet_2.id
  route_table_id = aws_route_table.dev_lambda_private_route_table.id
}

# Add a route to the NAT Gateway in the private route table
resource "aws_route" "dev_lambda_private_nat_route" {
  route_table_id         = aws_route_table.dev_lambda_private_route_table.id
  destination_cidr_block = "0.0.0.0/0" # Route all traffic to the NAT Gateway
  nat_gateway_id         = aws_nat_gateway.dev_lambda_nat_gateway.id
}