output "vpc_id" {
  description = "Identifier of the VPC created in LocalStack."
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Identifiers of the two public subnets."
  value       = module.network.public_subnet_ids
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the two public subnets."
  value       = module.network.public_subnet_cidrs
}

output "public_subnet_azs" {
  description = "Availability zones the public subnets were placed in."
  value       = module.network.availability_zones
}

output "private_subnet_ids" {
  description = "Identifiers of the private subnets."
  value       = module.network.private_subnet_ids
}

output "internet_gateway_id" {
  description = "Identifier of the internet gateway."
  value       = module.network.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "Identifiers of the NAT gateways."
  value       = module.network.nat_gateway_ids
}

output "public_route_table_id" {
  description = "Identifier of the shared public route table."
  value       = module.network.public_route_table_id
}

output "private_route_table_ids" {
  description = "Identifiers of the private route tables."
  value       = module.network.private_route_table_ids
}

output "alb_security_group_id" {
  description = "Identifier of the load balancer security group."
  value       = module.network.alb_security_group_id
}

output "app_security_group_id" {
  description = "Identifier of the workload security group."
  value       = module.network.app_security_group_id
}
