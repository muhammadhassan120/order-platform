module "rds" {
  source = "./module/rds"

  name_prefix           = "order-platform"
  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_name               = "mydb"
  db_username           = "appuser"
}