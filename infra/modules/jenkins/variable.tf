variable "name_prefix" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "jenkins_security_group_id" {
  type = string
}

variable "jenkins_instance_profile_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "key_pair_name" {
  type        = string
  description = "Existing EC2 key pair name"
}

variable "db_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for DB credentials"
}

variable "repo_url" {
  type        = string
  description = "Git repository URL"
}