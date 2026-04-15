output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN"
  value       = module.ecs.task_definition_arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.distribution_id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront.distribution_domain_name
}

output "invoice_bucket_name" {
  description = "S3 invoice bucket name"
  value       = module.s3.invoice_bucket_name
}

output "order_queue_url" {
  description = "Order queue URL"
  value       = module.async.order_queue_url
}

output "lambda_function_name" {
  description = "Order processor Lambda name"
  value       = module.async.lambda_function_name
}

output "jenkins_public_ip" {
  description = "Jenkins public IP"
  value       = module.jenkins.jenkins_public_ip
}
