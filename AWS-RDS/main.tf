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