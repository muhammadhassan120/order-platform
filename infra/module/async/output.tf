output "order_queue_url" {
  description = "URL of the SQS queue for order intake"
  value       = aws_sqs_queue.order_queue.url
}

output "order_queue_arn" {
  description = "ARN of the SQS order queue"
  value       = aws_sqs_queue.order_queue.arn
}

output "order_queue_name" {
  description = "Name of the SQS order queue"
  value       = aws_sqs_queue.order_queue.name
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dead_letter_queue.arn
}

output "dlq_queue_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.dead_letter_queue.name
}

output "audit_table_name" {
  description = "Name of the DynamoDB audit table"
  value       = aws_dynamodb_table.audit_trail.name
}

output "audit_table_arn" {
  description = "ARN of the DynamoDB audit table"
  value       = aws_dynamodb_table.audit_trail.arn
}

output "lambda_function_name" {
  description = "Name of the order processor Lambda"
  value       = aws_lambda_function.order_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the order processor Lambda"
  value       = aws_lambda_function.order_processor.arn
}