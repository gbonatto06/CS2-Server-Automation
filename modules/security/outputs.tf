output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.cs2_sg.id
}

output "key_name" {
  description = "SSH Key Pair name"
  value       = aws_key_pair.cs2_key_pair.key_name
}

output "admin_cidr" {
  description = "Administrator CIDR block"
  value       = local.admin_cidr
}
