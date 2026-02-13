variable "aws_region" {
  description = "Região da AWS onde a infraestrutura será provisionada."
  type        = string
  default     = "sa-east-1" # sa-east-1 para menor latência no brasil
}

variable "instance_type" {
  description = "Tipo da instância EC2." # Recomendado pelo menos uma instância t3.medium ou superior
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Nome do projeto utilizado para as tags dos recursos."
  type        = string
  default     = "cs2-server-automation"
}

variable "cs2_gslt_token" {
  description = "Token GSLT da Steam (AppID 730). Obtenha em: https://steamcommunity.com/dev/managegameservers"
  type        = string
  sensitive   = true
  # Valor será passado através do .tfvars
}

variable "cs2_server_password" {
  description = "Senha para entrar no servidor"
  type        = string
  default     = "" # Deixe vazio se quiser que o servidor seja público
}

variable "db_password" {
  description = "Senha root e do usuário admin do banco de dados MySQL"
  type        = string
  sensitive   = true
  # Valor deve ser passado via .tfvars
}