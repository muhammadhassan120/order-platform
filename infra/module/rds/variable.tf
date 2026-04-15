variable "name_prefix" {
  type        = string
  description = "Prefix for RDS resources"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the database"
}

variable "rds_security_group_id" {
  type        = string
  description = "The security group ID for the RDS instance"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "mydb"
}

variable "db_username" {
  type        = string
  description = "Master username for PostgreSQL"
  default     = "appuser"
}