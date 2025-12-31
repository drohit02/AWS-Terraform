data "aws_vpc" "default_vpc" {
  default = true
}

resource "aws_default_subnet" "default_subnet_1" {
  availability_zone = "ap-south-1a"
  tags = {
    Name = "default-subnet-1"
  }
}

resource "aws_default_subnet" "default_subnet_2" {
  availability_zone = "ap-south-1b"
  tags = {
    Name = "default-subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.48.0/20"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = data.aws_vpc.default_vpc.id
  cidr_block              = "172.31.64.0/20"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = data.aws_vpc.default_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

resource "aws_eip" "eip_nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "eip-nat-gateway"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip_nat_gateway.id
  subnet_id     = aws_default_subnet.default_subnet_1.id
  tags = {
    Name = "nat-gateway"
  }
}

resource "aws_route" "private_nat_gateway_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

########################################### AWS-Security-Group ###############################################
resource "aws_security_group" "opensearch_sg" {
  vpc_id = data.aws_vpc.default_vpc.id
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_ec2_sg.id]
  }
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_ec2_sg" {
  vpc_id = data.aws_vpc.default_vpc.id
  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = data.aws_vpc.default_vpc.id
  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.default_vpc.cidr_block]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}