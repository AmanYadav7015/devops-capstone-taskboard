output "aws_region" {
  description = "Region the stack is deployed in."
  value       = var.aws_region
}

output "vpc_id" {
  description = "Identifier of the VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Identifiers of the public subnets."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Identifiers of the private subnets."
  value       = module.network.private_subnet_ids
}

output "public_subnet_azs" {
  description = "Availability zones the public subnets were placed in."
  value       = module.network.availability_zones
}

output "internet_gateway_id" {
  description = "Identifier of the internet gateway."
  value       = module.network.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "Identifiers of the NAT gateways."
  value       = module.network.nat_gateway_ids
}

output "alb_security_group_id" {
  description = "Identifier of the public load balancer security group."
  value       = module.network.alb_security_group_id
}

output "app_security_group_id" {
  description = "Identifier of the TaskBoard workload security group."
  value       = module.network.app_security_group_id
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority bundle for the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "node_group_name" {
  description = "Name of the managed worker node group."
  value       = module.eks.node_group_name
}

output "node_group_arn" {
  description = "ARN of the managed worker node group."
  value       = module.eks.node_group_arn
}

output "cluster_addons" {
  description = "EKS managed addons installed on the cluster."
  value       = module.eks.cluster_addons
}

output "kubeconfig_command" {
  description = "Command that points kubectl at the provisioned cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}
