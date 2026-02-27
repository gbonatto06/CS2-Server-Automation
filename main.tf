# Networking - VPC, Subnet, Internet Gateway, Route Table
module "networking" {
  source     = "./modules/networking"
  aws_region = var.aws_region
}

# Security - Security Group, SSH Keys
module "security" {
  source = "./modules/security"
  vpc_id = module.networking.vpc_id
}

# Storage - S3 Bucket, Scripts Upload
module "storage" {
  source     = "./modules/storage"
  aws_region = var.aws_region
}

# Compute - IAM, EC2 Instance
module "compute" {
  source              = "./modules/compute"
  aws_region          = var.aws_region
  instance_type       = var.instance_type
  subnet_id           = module.networking.subnet_id
  security_group_id   = module.security.security_group_id
  key_name            = module.security.key_name
  bucket_name         = module.storage.bucket_name
  cs2_gslt_token      = var.cs2_gslt_token
  cs2_server_password = var.cs2_server_password
  db_password         = var.db_password
}
