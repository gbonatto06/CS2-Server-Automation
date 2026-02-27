variable "aws_region" {
  description = "AWS Region."
  type        = string
}

variable "instance_type" {
  description = "EC2 Instance Type."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance."
  type        = string
}

variable "security_group_id" {
  description = "Security Group ID for the EC2 instance."
  type        = string
}

variable "key_name" {
  description = "SSH Key Pair name."
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for scripts and backups."
  type        = string
}

variable "cs2_gslt_token" {
  description = "Steam Game Server Login Token."
  type        = string
  sensitive   = true
}

variable "cs2_server_password" {
  description = "Password to join the CS2 server."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "MySQL database password."
  type        = string
  sensitive   = true
}
