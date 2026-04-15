module "s3" {
  source = "./module/s3"

  name_prefix = "order-platform"
}




module "sns" {
  source = "./module/sns"

  name_prefix = "order-platform"
}