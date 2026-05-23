output "order_notifications_topic_arn" {
  description = "ARN of the order notifications SNS topic"
  value       = aws_sns_topic.order_notifications.arn
}

output "ops_alerts_topic_arn" {
  description = "ARN of the ops alerts SNS topic"
  value       = aws_sns_topic.ops_alerts.arn
}