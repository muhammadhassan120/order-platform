module "monitoring" {
  source = "./module/monitoring"

  name_prefix          = "order-platform"
  aws_region           = "us-east-2"
  ecs_cluster_name     = module.ecs.cluster_name
  ecs_service_name     = module.ecs.service_name
  order_queue_name     = module.async.order_queue_name
  dlq_queue_name       = module.async.dlq_queue_name
  lambda_function_name = module.async.lambda_function_name
  alb_arn_suffix       = module.alb.alb_arn_suffix
  db_instance_id       = module.rds.db_instance_id
  ops_alerts_topic_arn = module.sns.ops_alerts_topic_arn
}