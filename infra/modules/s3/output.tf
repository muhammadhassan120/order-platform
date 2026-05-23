output "invoice_bucket_id" {
  description = "S3 bucket ID for invoices"
  value       = aws_s3_bucket.invoices.id
}

output "invoice_bucket_arn" {
  description = "S3 bucket ARN for invoices"
  value       = aws_s3_bucket.invoices.arn
}

output "invoice_bucket_name" {
  description = "S3 bucket name for invoices"
  value       = aws_s3_bucket.invoices.bucket
}