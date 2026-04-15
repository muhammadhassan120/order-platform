module "jenkins" {
  source = "./module/jenkins"

  name_prefix                   = "order-platform"
  public_subnet_id              = module.vpc.public_subnet_id
  jenkins_security_group_id     = module.security.jenkins_security_group_id
  jenkins_instance_profile_name = module.security.jenkins_instance_profile_name
  instance_type                 = "t3.medium"
  key_pair_name = "order-platform-key"
}