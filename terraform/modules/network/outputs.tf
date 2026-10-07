output "vpc_id" {
  description = "Identifier of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Identifiers of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Identifiers of the private subnets."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "availability_zones" {
  description = "Availability zones the public subnets were placed in."
  value       = aws_subnet.public[*].availability_zone
}

output "internet_gateway_id" {
  description = "Identifier of the internet gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "Identifiers of the NAT gateways."
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "Identifier of the shared public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Identifiers of the per-subnet private route tables."
  value       = aws_route_table.private[*].id
}

output "alb_security_group_id" {
  description = "Identifier of the public load balancer security group."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Identifier of the TaskBoard workload security group."
  value       = aws_security_group.app.id
}
