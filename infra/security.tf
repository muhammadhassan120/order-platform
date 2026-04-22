module "security" {
  source = "./module/security"

  vpc_id      = module.vpc.vpc_id
  name_prefix = "order-platform"
  admin_cidr  = "182.189.97.243/32"
}