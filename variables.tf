variable "aws_region" {
  description = "AWS Region where the infrastructure will be provisioned."
  type        = string
  default     = "sa-east-1" # São Paulo for lower latency in Brazil
}

variable "instance_type" {
  description = "EC2 Instance Type. t3.medium or higher."
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Project name used for resource tagging."
  type        = string
  default     = "cs2-server-automation"
}

variable "cs2_gslt_token" {
  description = "Steam Game Server Login Token. Get it at: https://steamcommunity.com/dev/managegameservers"
  type        = string
  sensitive   = true

  # Basic validation to ensure the user didn't forget the variable
  validation {
    condition     = length(var.cs2_gslt_token) > 0
    error_message = "The GSLT Token cannot be empty."
  }
}

variable "cs2_server_password" {
  description = "Password required to join the CS2 server. Leave empty for public access."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_password" {
  description = "Root/Admin password for the MySQL database."
  type        = string
  sensitive   = true

  # Enforce minimum length
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The database password must be at least 8 characters long."
  }
}