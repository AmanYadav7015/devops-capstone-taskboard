variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes minor version of the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "Identifier of the VPC the cluster is created in."
  type        = string
}

variable "control_plane_subnet_ids" {
  description = "Subnets the EKS control plane cross-account elastic network interfaces are placed in. Must span at least two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.control_plane_subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "node_subnet_ids" {
  description = "Subnets the managed worker nodes are launched in."
  type        = list(string)

  validation {
    condition     = length(var.node_subnet_ids) >= 1
    error_message = "At least one subnet is required for the managed node group."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block allowed to reach the control plane security group on port 443."
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API server endpoint to the internet."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Expose the Kubernetes API server endpoint inside the VPC."
  type        = bool
  default     = true
}

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint. Narrow this before production use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_service_ipv4_cidr" {
  description = "CIDR block Kubernetes assigns service cluster IPs from. Must not overlap the VPC CIDR."
  type        = string
  default     = "172.20.0.0/16"
}

variable "cluster_enabled_log_types" {
  description = "Control plane log streams shipped to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "create_cloudwatch_log_group" {
  description = "Create the control plane CloudWatch log group ahead of the cluster so its retention is managed by Terraform."
  type        = bool
  default     = true
}

variable "cluster_log_retention_days" {
  description = "Retention of the control plane CloudWatch log group, in days."
  type        = number
  default     = 30
}

variable "cluster_addons" {
  description = "EKS managed addons installed after the node group is ready."
  type        = set(string)
  default     = ["coredns", "kube-proxy", "vpc-cni"]
}

variable "node_group_name" {
  description = "Name of the managed worker node group."
  type        = string
  default     = "workers"
}

variable "node_instance_types" {
  description = "EC2 instance types the managed node group may launch."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_ami_type" {
  description = "AMI family used by the managed node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  description = "Purchase model for the worker nodes, ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either ON_DEMAND or SPOT."
  }
}

variable "node_disk_size" {
  description = "Root volume size of each worker node, in GiB."
  type        = number
  default     = 20
}

variable "node_desired_size" {
  description = "Number of worker nodes the group starts with."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_labels" {
  description = "Kubernetes labels applied to every node in the group."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
