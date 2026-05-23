variable "name_prefix" {
  type        = string
  description = "Prefix used for ALB resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the ALB target group will be created"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the ALB"
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group ID for the ALB"
}

variable "target_group_port" {
  type        = number
  description = "Port for the target group"
  default     = 3000
}

variable "target_group_protocol" {
  type        = string
  description = "Protocol for the target group"
  default     = "HTTP"
}

variable "health_check_path" {
  type        = string
  description = "Health check path for the target group"
  default     = "/health"
}

variable "listener_port" {
  type        = number
  description = "Port for the ALB listener"
  default     = 80
}

variable "listener_protocol" {
  type        = string
  description = "Protocol for the ALB listener"
  default     = "HTTP"
}