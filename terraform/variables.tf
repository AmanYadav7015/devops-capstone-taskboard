variable "aws_region" {
  description = "AWS region every resource is created in."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix applied to the name of every resource."
  type        = string
  default     = "capstone-taskboard"
}

variable "environment" {
  description = "Deployment environment this stack represents."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging or prod."
  }
}

variable "owner" {
  description = "Value of the Owner tag, used for cost allocation."
  type        = string
  default     = "devops-capstone"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "capstone-taskboard-eks"
}

variable "cluster_version" {
  description = "Kubernetes minor version of the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones the subnets are spread across."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets. The rubric requires at least two."
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets that host the worker nodes."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets can reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all private subnets to keep classroom cost down."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API server endpoint to the internet."
  type        = bool
  default     = true
}

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EC2 instance types the managed node group may launch."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Purchase model for the worker nodes, ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
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

variable "node_disk_size" {
  description = "Root volume size of each worker node, in GiB."
  type        = number
  default     = 20
}

variable "backend_port" {
  description = "TCP port the TaskBoard backend listens on."
  type        = number
  default     = 8000
}

variable "skip_aws_api_checks" {
  description = "Skip the provider credential, metadata and account id lookups. Set to true only to validate or plan this configuration without an AWS account."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
