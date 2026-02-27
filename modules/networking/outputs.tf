output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.cs2_vpc.id
}

output "subnet_id" {
  description = "Public Subnet ID"
  value       = aws_subnet.cs2_subnet.id
}
