variable "aws_region" {
  description = "Região da AWS onde o servidor será criado"
  type        = string
  default     = "sa-east-1"
}

variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Nome do projeto para as tags"
  type        = string
  default     = "cs2-server-automation"
}
