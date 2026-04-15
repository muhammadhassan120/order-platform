module "alb" {
  source = "./module/alb"

  name_prefix           = "order-platform"
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id

  target_group_port     = 3000
  target_group_protocol = "HTTP"
  health_check_path     = "/health"

  listener_port     = 80
  listener_protocol = "HTTP"
}