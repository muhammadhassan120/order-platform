output "db_endpoint" {
  description = "The connection endpoint for the RDS database"
  value       = aws_db_instance.default.endpoint
}

output "db_secret_arn" {
  description = "The ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "db_instance_id" {
  description = "The DB instance identifier"
  value       = aws_db_instance.default.id
}