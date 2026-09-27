module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "platform-lab"
  kubernetes_version = "1.35"

  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_groups = {
    bootstrap = {
      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 1
      desired_size = 1
    }
  }

  tags = {
    Project = "kubernetes-platform-lab"
  }
}
