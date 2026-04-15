variable "name_prefix" {
  type        = string
  description = "Prefix for ECS autoscaling resources"
}

variable "cluster_name" {
  type        = string
  description = "ECS cluster name"
}

variable "service_name" {
  type        = string
  description = "ECS service name"
}

variable "min_capacity" {
  type        = number
  description = "Minimum ECS desired count"
  default     = 1
}

variable "max_capacity" {
  type        = number
  description = "Maximum ECS desired count"
  default     = 3
}

variable "cpu_target" {
  type        = number
  description = "CPU utilization target percentage"
  default     = 60
}