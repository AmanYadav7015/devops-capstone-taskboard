locals {
  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
  }, var.extra_tags)
}

module "network" {
  source = "./modules/network"

  name_prefix          = var.project_name
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  backend_port         = var.backend_port
  tags                 = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = module.network.vpc_id
  vpc_cidr_block           = module.network.vpc_cidr_block
  control_plane_subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids          = module.network.private_subnet_ids

  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  cluster_public_access_cidrs    = var.cluster_public_access_cidrs

  node_group_name     = "taskboard-workers"
  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  node_labels = {
    workload = "taskboard"
  }

  tags = local.common_tags
}
