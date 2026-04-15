variable "name_prefix" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "lambda_role_arn" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type    = string
  default = "mydb"
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "invoice_bucket_id" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}