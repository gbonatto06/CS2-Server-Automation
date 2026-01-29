# Busca o ID da conta AWS para criar um nome de bucket único globalmente
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "cs2-server-backups-${data.aws_caller_identity.current.account_id}"
}

data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

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
  filename        = "${path.module}/cs2-server-key.pem"
  file_permission = "0400"
}

# Infra da rede
resource "aws_vpc" "cs2_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "cs2-vpc" }
}

resource "aws_internet_gateway" "cs2_igw" {
  vpc_id = aws_vpc.cs2_vpc.id
}

resource "aws_subnet" "cs2_subnet" {
  vpc_id                  = aws_vpc.cs2_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
}

resource "aws_route_table" "cs2_rt" {
  vpc_id = aws_vpc.cs2_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cs2_igw.id
  }
}

resource "aws_route_table_association" "cs2_rta" {
  subnet_id      = aws_subnet.cs2_subnet.id
  route_table_id = aws_route_table.cs2_rt.id
}

# Criação do bucket via CLI para evitar destruição no 'terraform destroy'
resource "null_resource" "cs2_backups_setup" {
  provisioner "local-exec" {
    command = <<EOT
      aws s3api head-bucket --bucket ${local.bucket_name} 2>/dev/null || \
      aws s3api create-bucket --bucket ${local.bucket_name} --region ${var.aws_region} --create-bucket-configuration LocationConstraint=${var.aws_region}
    EOT
  }
}

resource "aws_iam_role" "ec2_s3_role" {
  name = "cs2-ec2-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cs2-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name
}

resource "aws_security_group" "cs2_sg" {
  name        = "cs2-server-sg"
  vpc_id      = aws_vpc.cs2_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  ingress {
    from_port   = 27015
    to_port     = 27015
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27015
    to_port     = 27015
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "cs2_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cs2_subnet.id
  vpc_security_group_ids = [aws_security_group.cs2_sg.id]
  key_name               = aws_key_pair.cs2_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = templatefile("${path.module}/scripts/install_cs2.sh", {
    gslt_token      = trimspace(var.cs2_gslt_token)
    s3_bucket_name  = local.bucket_name
    server_password = var.cs2_server_password
  })

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = { Name = "CS2-Dedicated-Server" }

  depends_on = [null_resource.cs2_backups_setup]
}