module "jenkins" {
  source = "./module/jenkins"

  name_prefix                   = "order-platform"
  public_subnet_id              = module.vpc.public_subnet_ids[0]
  jenkins_security_group_id     = module.security.jenkins_security_group_id
  jenkins_instance_profile_name = module.security.jenkins_instance_profile_name
  key_pair_name                 = "order-platform-key"

  db_secret_arn = module.rds.db_secret_arn
  repo_url      = "https://github.com/muhammadhassan120/order-platform.git"

  depends_on = [
    module.rds,
    module.async
  ]
}