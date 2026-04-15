variable "name_prefix" {
  type        = string
  description = "Prefix for Lambda IAM resources"
}

variable "db_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for database credentials"
}

variable "audit_table_arn" {
  type        = string
  description = "DynamoDB audit table ARN"
}

variable "invoice_bucket_arn" {
  type        = string
  description = "S3 invoice bucket ARN"
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for order notifications"
}

variable "order_queue_arn" {
  type        = string
  description = "SQS order queue ARN"
}