module "ecr" {
  source = "./module/ecr"

  repository_name = "order-platform-repo"
}