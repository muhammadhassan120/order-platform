module "vpc" {
  source = "./module/vpc"

  vpc_cidr = "10.0.0.0/16"

  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_b_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.11.0/24"
  private_subnet_b_cidr = "10.0.12.0/24"

  public_availability_zone_a  = "us-east-2a"
  public_availability_zone_b  = "us-east-2b"
  private_availability_zone_a = "us-east-2a"
  private_availability_zone_b = "us-east-2b"
}