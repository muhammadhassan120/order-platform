# ==================== DB SUBNET GROUP ====================
resource "aws_db_subnet_group" "default" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

# ==================== RANDOM PASSWORD ====================
resource "random_password" "db_password" {
  length  = 20
  special = false
}

# ==================== SECRETS MANAGER ====================
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.name_prefix}-db-credentials-v6-lastest"
  description = "Holds the PostgreSQL database credentials"
}

# ==================== RDS INSTANCE ====================
resource "aws_db_instance" "default" {
  allocated_storage       = 20
  storage_type            = "gp3"
  db_subnet_group_name    = aws_db_subnet_group.default.name
  db_name                 = var.db_name

  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"

  username                = var.db_username
  password                = random_password.db_password.result

  parameter_group_name    = "default.postgres16"
  skip_final_snapshot     = true

  vpc_security_group_ids  = [var.rds_security_group_id]

  publicly_accessible     = false
  multi_az                = false
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-rds"
  }
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id = aws_secretsmanager_secret.db_password.id

  secret_string = jsonencode({
    host     = aws_db_instance.default.address
    port     = aws_db_instance.default.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db_password.result
  })
}