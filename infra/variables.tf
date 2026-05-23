variable "aws_region" {
  description = "AWS region for all deployable resources."
  type        = string
  default     = "us-east-2"
}

variable "name_prefix" {
  description = "Shared prefix for order platform resources."
  type        = string
  default     = "order-platform"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must use only lowercase letters, numbers, and hyphens."
  }
}

variable "rds_name_prefix" {
  description = "Prefix used by the RDS module. Kept separate to preserve the current DB identifier."
  type        = string
  default     = "order-platform-latet"
}

variable "admin_cidr" {
  description = "Admin CIDR allowed to reach Jenkins SSH and port 8080."
  type        = string
  default     = "182.189.94.102/32"

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block such as 203.0.113.10/32."
  }
}

variable "key_pair_name" {
  description = "Existing AWS EC2 key pair name used by the Jenkins instance."
  type        = string
  default     = "order-platform-key"
}

variable "repo_url" {
  description = "Git repository URL cloned by Jenkins-related provisioning steps."
  type        = string
  default     = "https://github.com/muhammadhassan120/order-platform.git"
}

variable "db_name" {
  description = "Application PostgreSQL database name."
  type        = string
  default     = "mydb"
}

variable "db_username" {
  description = "Application PostgreSQL username."
  type        = string
  default     = "appuser"
}

variable "ses_from_email" {
  description = "Verified SES sender email in us-east-2."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.ses_from_email))
    error_message = "ses_from_email must be a valid email address verified in SES."
  }
}

variable "rds_skip_final_snapshot" {
  description = "Whether to skip a final RDS snapshot on destroy. Demo default keeps destroy simple."
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Whether to enable RDS deletion protection."
  type        = bool
  default     = false
}
