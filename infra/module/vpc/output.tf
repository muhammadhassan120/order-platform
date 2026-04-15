output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Primary public subnet ID"
  value       = aws_subnet.public_a.id
}

output "private_subnet_id" {
  description = "Primary private subnet ID"
  value       = aws_subnet.private_a.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "vpc" {
  description = "All VPC related outputs"
  value = {
    vpc_id             = aws_vpc.main.id
    public_subnet_id   = aws_subnet.public_a.id
    private_subnet_id  = aws_subnet.private_a.id
    public_subnet_ids  = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    private_subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    nat_gateway_id     = aws_nat_gateway.main.id
    igw_id             = aws_internet_gateway.main.id
  }
}