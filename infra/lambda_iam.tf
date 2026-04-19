module "lambda_iam" {
  source = "./module/lambda_iam"

  name_prefix                   = "order-platform"
  db_secret_arn                 = module.rds.db_secret_arn
  audit_table_arn               = module.async.audit_table_arn
  invoices_bucket_arn           = module.s3.invoice_bucket_arn
  order_notifications_topic_arn = module.sns.order_notifications_topic_arn
  ops_alerts_topic_arn          = module.sns.ops_alerts_topic_arn
  order_queue_arn               = module.async.order_queue_arn
  ses_from_email                = var.ses_from_email
}