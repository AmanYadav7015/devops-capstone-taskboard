variable "name_prefix" {
  description = "Prefix applied to the Name tag of every resource created by this module."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster the subnets are tagged for, so the AWS Load Balancer Controller can discover them."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, for example 10.20.0.0/16."
  }
}

variable "availability_zones" {
  description = "Availability zones the subnets are spread across. At least two are required for an EKS control plane."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for a highly available EKS control plane."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, one per availability zone."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnets are required."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets that host the EKS worker nodes."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnets are required."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets can reach the internet for image pulls."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across every private subnet instead of one per availability zone."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames on the VPC."
  type        = bool
  default     = true
}

variable "backend_port" {
  description = "TCP port the TaskBoard backend listens on behind the load balancer."
  type        = number
  default     = 8000
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
