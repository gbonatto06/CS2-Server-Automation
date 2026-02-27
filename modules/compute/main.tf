# Ubuntu AMI Lookup
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

resource "aws_iam_role_policy" "s3_scoped" {
  name = "cs2-s3-scoped-access"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cs2-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name
}

# EC2 Instance
#trivy:ignore:AVD-AWS-0028
resource "aws_instance" "cs2_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # IMDSv2: Requires token-based access to instance metadata (169.254.169.254),
  # blocking SSRF attacks that could exfiltrate IAM credentials via simple GET requests.
  # hop_limit=1 prevents Docker containers from reaching the metadata endpoint.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 120
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "CS2-Dedicated-Server" }

  # User Data
  #trivy:ignore:AVD-AWS-0029
  user_data = <<-EOF
    #!/bin/bash
    # Debug user-data logs
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    # Export Terraform Variables to Environment Variables
    export server_password="${var.cs2_server_password}"
    export db_password="${var.db_password}"
    export gslt_token="${var.cs2_gslt_token}"
    export s3_bucket_name="${var.bucket_name}"

    # Install dependencies required to fetch and unzip scripts
    apt-get update
    apt-get install -y awscli unzip

    # S3 Download
    MAX_RETRIES=20
    COUNT=0
    SUCCESS=0

    echo "Waiting for scripts.zip in S3"

    while [ $COUNT -lt $MAX_RETRIES ]; do
        if aws s3 ls "s3://${var.bucket_name}/scripts.zip"; then
            echo "File found, Downloading"
            aws s3 cp "s3://${var.bucket_name}/scripts.zip" /tmp/scripts.zip
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
    aws_iam_role_policy.s3_scoped
  ]
}
