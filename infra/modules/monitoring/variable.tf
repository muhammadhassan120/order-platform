variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "order_queue_name" {
  type = string
}

variable "dlq_queue_name" {
  type = string
}

variable "lambda_function_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "db_instance_id" {
  type = string
}

variable "ops_alerts_topic_arn" {
  type = string
}