variable "name_prefix" {
  type        = string
  description = "Prefix for security and IAM resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where security groups will be created"
}

variable "admin_cidr" {
  type        = string
  description = "Admin CIDR allowed to access Jenkins"
}