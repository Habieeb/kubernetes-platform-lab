module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "platform-lab"
  kubernetes_version = "1.35"

  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  security_group_additional_rules = {
    ingress_nodes_443 = {
      description                = "Allow EKS worker nodes to reach the cluster API"
      protocol                   = "tcp"
      from_port                  = 443
      to_port                    = 443
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  eks_managed_node_groups = {
    bootstrap = {
      instance_types = ["t3.small"]

      ami_id                     = var.node_ami_id
      enable_bootstrap_user_data = true

      min_size     = 1
      max_size     = 1
      desired_size = 1
    }
  }

  tags = {
    Project = "kubernetes-platform-lab"
  }
}
