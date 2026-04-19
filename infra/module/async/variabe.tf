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
  type = string
}

variable "db_port" {
  type = number
}

variable "invoice_bucket_id" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "ops_alert_topic_arn" {
  type = string
}

variable "ses_from_email" {
  type = string
}