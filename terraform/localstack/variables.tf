variable "aws_region" {
  description = "Region reported to the LocalStack endpoint."
  type        = string
  default     = "ap-south-1"
}

variable "localstack_endpoint" {
  description = "Base URL of the LocalStack edge port."
  type        = string
  default     = "http://localhost:4566"
}

variable "localstack_access_key" {
  description = "Placeholder access key. LocalStack ignores it and it is not a real credential."
  type        = string
  default     = "test"
}

variable "localstack_secret_key" {
  description = "Placeholder secret key. LocalStack ignores it and it is not a real credential."
  type        = string
  default     = "test"
}

variable "project_name" {
  description = "Prefix applied to the name of every resource."
  type        = string
  default     = "capstone-taskboard"
}

variable "environment" {
  description = "Deployment environment this stack represents."
  type        = string
  default     = "localstack"
}

variable "cluster_name" {
  description = "Cluster name the subnets are tagged for, matching the real AWS stack."
  type        = string
  default     = "capstone-taskboard-eks"
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
  description = "CIDR blocks of the public subnets."
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways. LocalStack community emulates the API calls but no traffic is forwarded."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all private subnets."
  type        = bool
  default     = true
}
