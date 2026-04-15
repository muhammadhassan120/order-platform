module "ecs_autoscaling" {
  source = "./module/ecs-asg"

  name_prefix  = "order-platform"
  cluster_name = module.ecs.cluster_name
  service_name = module.ecs.service_name
  min_capacity = 1
  max_capacity = 3
  cpu_target   = 60
}