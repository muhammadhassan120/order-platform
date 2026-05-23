variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
}

variable "service_name" {
  type        = string
  description = "Name of the ECS service"
}

variable "task_family" {
  type        = string
  description = "Family name for the ECS task definition"
}

variable "container_name" {
  type        = string
  description = "Name of the container"
}

variable "container_port" {
  type        = number
  description = "Port exposed by the container"
  default     = 3000
}

variable "container_image" {
  type        = string
  description = "Full container image URI, usually from ECR repository URL with tag"
}

variable "cpu" {
  type        = number
  description = "CPU units for the task"
  default     = 256
}

variable "memory" {
  type        = number
  description = "Memory in MiB for the task"
  default     = 512
}

variable "desired_count" {
  type        = number
  description = "Number of ECS tasks to run"
  default     = 1
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ECS tasks"
}

variable "ecs_security_group_id" {
  type        = string
  description = "Security group ID for ECS tasks"
}

variable "target_group_arn" {
  type        = string
  description = "Target group ARN for the ECS service"
}

variable "execution_role_arn" {
  type        = string
  description = "ECS task execution role ARN"
}

variable "task_role_arn" {
  type        = string
  description = "ECS task role ARN"
}

variable "aws_region" {
  type        = string
  description = "AWS region for logs"
}

variable "log_group_name" {
  type        = string
  description = "CloudWatch log group name for ECS container logs"
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Plain environment variables for container"
  default     = []
}

variable "secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  description = "Secrets Manager or SSM secrets for container"
  default     = []
}

