module "ecs" {
  source                = "./module/ecs"
  cluster_name          = "order-platform-cluster"
  service_name          = "order-platform-service"
  task_family           = "order-platform-task"
  container_name        = "order-api"
  container_port        = 3000
  container_image       = "${module.ecr.repository_url}:latest"
  cpu                   = 256
  memory                = 512
  desired_count         = 1
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security.ecs_security_group_id
  target_group_arn      = module.alb.target_group_arn
  execution_role_arn    = module.security.ecs_task_execution_role_arn
  task_role_arn         = module.security.ecs_task_role_arn
  aws_region            = "us-east-2"
  log_group_name        = "/ecs/order-platform"

  environment_variables = [
    {
      name  = "NODE_ENV"
      value = "production"
    },
    {
      name  = "PORT"
      value = "3000"
    },
    {
      name  = "AWS_REGION"
      value = "us-east-2"
    },
    {
      name  = "ORDER_QUEUE_URL"
      value = module.async.order_queue_url
    },
    {
      name  = "AUTH_ENABLED"
      value = "false"
    }
  ]

  secrets = [
    {
      name      = "DB_SECRET_ARN"
      valueFrom = module.rds.db_secret_arn
    }
  ]

  depends_on = [module.alb, module.rds, module.async]
}