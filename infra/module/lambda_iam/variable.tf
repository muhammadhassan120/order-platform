variable "name_prefix" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "audit_table_arn" {
  type = string
}

variable "invoices_bucket_arn" {
  type = string
}

variable "order_notifications_topic_arn" {
  type = string
}

variable "order_queue_arn" {
  type = string
}

variable "ses_from_email" {
  type = string
}