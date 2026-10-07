# VPC and EKS for the TaskBoard capstone.
#
# COST WARNING. This is not free-tier. Roughly:
#   EKS control plane      $0.10/hour
#   2 x t3.medium workers  $0.08/hour
#   NAT gateway            $0.05/hour plus data
# About $0.23/hour, so ~$5.50 a day. Run `terraform destroy` when finished.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # Workers live in private subnets and reach the internet through NAT.
  # Load balancers live in the public ones.
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  # EKS discovers subnets by these tags. Without them the AWS load balancer
  # controller cannot work out where to place a load balancer.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint so kubectl works from a laptop. A production cluster would
  # restrict this to known CIDRs, or keep it private and reach it over a VPN.
  cluster_endpoint_public_access = true

  # Grants the identity running terraform admin on the cluster, so kubectl
  # works immediately after apply without a separate aws-auth edit.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    main = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 4
      desired_size   = var.node_desired_size

      # Managed node groups handle the AMI, the bootstrap and draining during
      # an upgrade, which is why they are preferred over self-managed ones.
      capacity_type = "ON_DEMAND"
    }
  }
}
