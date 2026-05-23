output "public_ip" {
  description = "Public IP of Jenkins EC2 instance"
  value       = aws_instance.jenkins.public_ip
}

output "instance_id" {
  description = "Instance ID of Jenkins EC2 instance"
  value       = aws_instance.jenkins.id
}
