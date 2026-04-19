module "async" {
  source = "./module/async"

  name_prefix              = "order-platform"
  private_subnet_ids       = module.vpc.private_subnet_ids
  lambda_security_group_id = module.security.lambda_security_group_id

  lambda_role_arn = module.lambda_iam.lambda_role_arn

  db_secret_arn = module.rds.db_secret_arn
  db_host       = split(":", module.rds.db_endpoint)[0]
  db_name       = "mydb"
  db_port       = 5432
  ses_from_email = var.ses_from_email

  invoice_bucket_id = module.s3.invoice_bucket_name
  sns_topic_arn     = module.sns.order_notifications_topic_arn
}