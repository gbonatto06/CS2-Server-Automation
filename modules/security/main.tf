# Identify Administrator IP for SSH access
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  admin_cidr = ["${chomp(data.http.my_ip.response_body)}/32"]
}

# Security Group
resource "aws_security_group" "cs2_sg" {
  name        = "cs2-server-sg"
  description = "CS2 Server Security: Admin Access Restricted"
  vpc_id      = var.vpc_id

  # SSH - Admin Only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.admin_cidr
    description = "SSH Access - Admin"
  }

  # CS2 Game Traffic - Public
  ingress {
    from_port   = 27015
    to_port     = 27015
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "CS2 Game Traffic (UDP) - Public"
  }

  # RCON - Admin Only
  ingress {
    from_port   = 27015
    to_port     = 27015
    protocol    = "tcp"
    cidr_blocks = local.admin_cidr
    description = "RCON Access - Admin"
  }

  # Grafana - Admin Only
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = local.admin_cidr
    description = "Grafana Dashboard - Admin"
  }

  # Prometheus - Admin Only
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = local.admin_cidr
    description = "Prometheus UI - Admin"
  }

  # Egress - Open
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Outbound traffic for updates/S3/Steam"
  }

  tags = { Name = "cs2-server-security-group" }
}

# SSH Keys Generation
resource "tls_private_key" "cs2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cs2_key_pair" {
  key_name   = "cs2-server-key"
  public_key = tls_private_key.cs2_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.cs2_key.private_key_pem
  filename        = "${path.root}/cs2-server-key.pem"
  file_permission = "0400"
}
