module "cloudfront" {
  source = "./module/cloudfront"

  name_prefix        = "order-platform"
  origin_domain_name = module.alb.alb_dns_name
}
