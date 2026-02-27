output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.cs2_server.public_ip
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.cs2_server.id
}
