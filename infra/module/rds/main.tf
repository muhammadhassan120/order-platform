resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

resource "aws_db_instance" "default" {
  identifier             = "${var.name_prefix}-db"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.10"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [var.rds_security_group_id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  deletion_protection    = false

  tags = {
    Name = "${var.name_prefix}-db"
  }
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.name_prefix}-db-credentials-order-processing-secret-latest-app"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-db-credentials-order-processing"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id

  secret_string = jsonencode({
    host     = aws_db_instance.default.address
    port     = aws_db_instance.default.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db_password.result
  })
}




output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}