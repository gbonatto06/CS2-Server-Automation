# Retrieve AWS Account ID to create a globally unique bucket name
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "cs2-server-backups-${data.aws_caller_identity.current.account_id}"
}

# S3 Bucket Creation (via CLI to prevent destruction on 'terraform destroy')
resource "null_resource" "cs2_backups_setup" {
  provisioner "local-exec" {
    command = <<EOT
      aws s3api head-bucket --bucket ${local.bucket_name} 2>/dev/null || aws s3api create-bucket --bucket ${local.bucket_name} --region ${var.aws_region} --create-bucket-configuration LocationConstraint=${var.aws_region}
      aws s3api put-public-access-block --bucket ${local.bucket_name} --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
      aws s3api put-bucket-encryption --bucket ${local.bucket_name} --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
      aws s3api put-bucket-versioning --bucket ${local.bucket_name} --versioning-configuration Status=Enabled
    EOT
  }
}

# Archive scripts folder
data "archive_file" "scripts_zip" {
  type        = "zip"
  source_dir  = "${path.root}/scripts"
  output_path = "${path.root}/scripts.zip"
}

# Upload scripts to S3
resource "aws_s3_object" "scripts_upload" {
  bucket = local.bucket_name
  key    = "scripts.zip"
  source = data.archive_file.scripts_zip.output_path
  # Etag ensures Terraform updates the file in S3 if the zip changes
  etag = data.archive_file.scripts_zip.output_md5

  depends_on = [null_resource.cs2_backups_setup]
}
