locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = "devops-capstone"
    ManagedBy   = "terraform"
    Backend     = "localstack"
  }
}

module "network" {
  source = "../modules/network"

  name_prefix          = var.project_name
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  tags = local.common_tags
}
