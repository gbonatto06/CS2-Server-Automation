# Retrieve AWS Account ID to create a globally unique bucket name
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "cs2-server-backups-${data.aws_caller_identity.current.account_id}"
}

# Identify Administrator IP for SSH access
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

# Ubuntu AMI Lookup
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
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
  filename        = "${path.module}/cs2-server-key.pem"
  file_permission = "0400"
}

# Network Infrastructure
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

# S3 Bucket Creation (via CLI to prevent destruction on 'terraform destroy')
resource "null_resource" "cs2_backups_setup" {
  provisioner "local-exec" {
    command = <<EOT
      aws s3api head-bucket --bucket ${local.bucket_name} 2>/dev/null || \
      aws s3api create-bucket --bucket ${local.bucket_name} --region ${var.aws_region} --create-bucket-configuration LocationConstraint=${var.aws_region}
    EOT
  }
}

# IAM Roles and Policies
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

# Security Groups
locals {
  admin_cidr = ["${chomp(data.http.my_ip.response_body)}/32"]
}

resource "aws_security_group" "cs2_sg" {
  name        = "cs2-server-sg"
  description = "CS2 Server Security: Admin Access Restricted"
  vpc_id      = aws_vpc.cs2_vpc.id

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

# Archive scripts folder
data "archive_file" "scripts_zip" {
  type        = "zip"
  source_dir  = "${path.module}/scripts"
  output_path = "${path.module}/scripts.zip"
}

# Upload the zip file instead of a single script
resource "aws_s3_object" "scripts_upload" {
  bucket = local.bucket_name
  key    = "scripts.zip"
  source = data.archive_file.scripts_zip.output_path
  # Etag ensures Terraform updates the file in S3 if the zip changes
  etag   = data.archive_file.scripts_zip.output_md5
  
  depends_on = [null_resource.cs2_backups_setup]
}

# EC2 Instance
resource "aws_instance" "cs2_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cs2_subnet.id
  vpc_security_group_ids = [aws_security_group.cs2_sg.id]
  key_name               = aws_key_pair.cs2_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
  }

  tags = { Name = "CS2-Dedicated-Server" }

  # User Data
  user_data = <<-EOF
    #!/bin/bash
    # Debug user-data logs
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    
    # Export Terraform Variables to Environment Variables
    export server_password="${var.cs2_server_password}"
    export db_password="${var.db_password}"
    export gslt_token="${var.cs2_gslt_token}"
    export s3_bucket_name="${local.bucket_name}"
    
    # Install dependencies required to fetch and unzip scripts
    apt-get update
    apt-get install -y awscli unzip
    
    # S3 Download
    MAX_RETRIES=20
    COUNT=0
    SUCCESS=0
    
    echo "Waiting for scripts.zip in S3"
    
    while [ $COUNT -lt $MAX_RETRIES ]; do
        if aws s3 ls "s3://${local.bucket_name}/scripts.zip"; then
            echo "File found, Downloading"
            aws s3 cp "s3://${local.bucket_name}/scripts.zip" /tmp/scripts.zip
            if [ -f /tmp/scripts.zip ]; then
                SUCCESS=1
                break
            fi
        fi
        echo "Waiting for S3 upload. Attempt $COUNT/$MAX_RETRIES"
        sleep 10
        COUNT=$((COUNT+1))
    done

    if [ $SUCCESS -eq 0 ]; then
        echo "Critical Error: Failed to download scripts.zip after multiple attempts."
        exit 1
    fi


    # Prepare Directory
    echo "Unzipping scripts"
    mkdir -p /tmp/install
    unzip /tmp/scripts.zip -d /tmp/install
    ls -R /tmp/install
    
    # Execute Orchestrator
    chmod +x /tmp/install/install_cs2.sh
    
    # Navigate to script dir to ensure relative paths work
    cd /tmp/install
    ./install_cs2.sh
  EOF

  depends_on = [
    
    aws_s3_object.scripts_upload,
    aws_iam_role_policy_attachment.s3_access
    
    ]
}