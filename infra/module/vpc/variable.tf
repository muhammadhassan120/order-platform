variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_a_cidr" {
  type        = string
  description = "CIDR block for public subnet A"
}

variable "public_subnet_b_cidr" {
  type        = string
  description = "CIDR block for public subnet B"
}

variable "private_subnet_a_cidr" {
  type        = string
  description = "CIDR block for private subnet A"
}

variable "private_subnet_b_cidr" {
  type        = string
  description = "CIDR block for private subnet B"
}

variable "public_availability_zone_a" {
  type        = string
  description = "AZ for public subnet A"
}

variable "public_availability_zone_b" {
  type        = string
  description = "AZ for public subnet B"
}

variable "private_availability_zone_a" {
  type        = string
  description = "AZ for private subnet A"
}

variable "private_availability_zone_b" {
  type        = string
  description = "AZ for private subnet B"
}