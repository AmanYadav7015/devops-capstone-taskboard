output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority bundle for the cluster."
  value       = try(aws_eks_cluster.this.certificate_authority[0].data, null)
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL, used to wire IAM roles for service accounts."
  value       = try(aws_eks_cluster.this.identity[0].oidc[0].issuer, null)
}

output "cluster_security_group_id" {
  description = "Identifier of the control plane security group managed by this module."
  value       = aws_security_group.cluster.id
}

output "cluster_primary_security_group_id" {
  description = "Identifier of the security group EKS creates for the cluster."
  value       = try(aws_eks_cluster.this.vpc_config[0].cluster_security_group_id, null)
}

output "cluster_iam_role_arn" {
  description = "ARN of the control plane IAM role."
  value       = aws_iam_role.cluster.arn
}

output "node_group_name" {
  description = "Name of the managed worker node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN of the managed worker node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Lifecycle status of the managed worker node group."
  value       = aws_eks_node_group.this.status
}

output "node_iam_role_arn" {
  description = "ARN of the worker node instance role."
  value       = aws_iam_role.node.arn
}

output "cluster_addons" {
  description = "EKS managed addons installed on the cluster."
  value       = [for addon in aws_eks_addon.this : addon.addon_name]
}

output "cluster_log_group_name" {
  description = "Name of the control plane CloudWatch log group, when this module manages it."
  value       = try(aws_cloudwatch_log_group.cluster[0].name, null)
}
