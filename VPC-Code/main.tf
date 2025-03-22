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

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.2.0/24" # Adjusted CIDR block
  availability_zone       = "ap-south-1b"   # Ensure you are using valid AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "default-subnet-b"
  }
}

# Create Private Subnets with non-overlapping CIDR blocks
resource "aws_subnet" "private_subnet_x" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.3.0/24" # Adjusted CIDR block
  availability_zone = "ap-south-1a"

  tags = {
    Name = "private-subnet-x"
  }
}

resource "aws_subnet" "private_subnet_y" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.4.0/24" # Adjusted CIDR block
  availability_zone = "ap-south-1b"

  tags = {
    Name = "private-subnet-y"
  }
}

# Create Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc" # Correct way to associate EIP with VPC
}

# Create NAT Gateway in one of the public subnets
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id

  tags = {
    Name = "default-nat-gateway"
  }
}

# Create Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_subnet_x_association" {
  subnet_id      = aws_subnet.private_subnet_x.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_y_association" {
  subnet_id      = aws_subnet.private_subnet_y.id
  route_table_id = aws_route_table.private_route_table.id
}