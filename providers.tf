# Terraform settings & providers

terraform {
  # 🇺🇸 Define required providers and versions for the project
  # 🇧🇷 Define os provedores necessários e suas versões para o projeto
  required_providers {
    # 🇺🇸 Main provider to manage AWS resources (EC2, S3, Security Groups)
    # 🇧🇷 Provedor principal para gerenciar recursos AWS (EC2, S3, Security Groups)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # 🇺🇸 Used to fetch your current public IP to secure the instance
    # 🇧🇷 Usado para buscar seu IP público atual para proteger a instância
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4.5"
    }
    # 🇺🇸 Used to generate SSH Key Pairs automatically during deployment
    # 🇧🇷 Usado para gerar o par de chaves SSH automaticamente durante o deploy
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # 🇺🇸 Used to save the private key (.pem) and other files locally
    # 🇧🇷 Usado para salvar a chave privada (.pem) e outros arquivos localmente
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # 🇺🇸 Minimum Terraform version required
  # 🇧🇷 Versão mínima do Terraform necessária
  required_version = ">= 1.2.0"
}

# Provider Configuration

# 🇺🇸 AWS Provider initialized with the region from variables
# 🇧🇷 Provedor AWS inicializado com a região definida nas variáveis
provider "aws" {
  region = var.aws_region
}

# 🇺🇸 HTTP Provider (no extra config required, used for IP detection)
# 🇧🇷 Provedor HTTP (sem configuração extra, usado para detecção de IP)
provider "http" {}