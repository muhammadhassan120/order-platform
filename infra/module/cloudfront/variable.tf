variable "name_prefix" {
  type        = string
  description = "Prefix for CloudFront resources"
}

variable "origin_domain_name" {
  type        = string
  description = "DNS name of the ALB origin"
}

variable "enabled" {
  type        = bool
  description = "Whether the distribution is enabled"
  default     = true
}

variable "price_class" {
  type        = string
  description = "CloudFront price class"
  default     = "PriceClass_All"
}

variable "origin_http_port" {
  type        = number
  description = "HTTP port used by the origin"
  default     = 80
}

variable "origin_https_port" {
  type        = number
  description = "HTTPS port used by the origin"
  default     = 443
}

variable "origin_protocol_policy" {
  type        = string
  description = "Protocol CloudFront uses to reach the origin"
  default     = "http-only"
}

variable "viewer_protocol_policy" {
  type        = string
  description = "Protocol policy for viewers connecting to CloudFront"
  default     = "allow-all"
}
