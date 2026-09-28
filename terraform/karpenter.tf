module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # Karpenter controller -> AWS authentication.
  # EKS module v21 uses Pod Identity.
  create_pod_identity_association = true

  # IAM role used by EC2 nodes launched by Karpenter.
  create_node_iam_role = true

  # Create SQS/EventBridge resources so Karpenter can react to
  # Spot interruption, rebalance and instance state events.
  enable_spot_termination = true

  tags = {
    Project   = "kubernetes-platform-lab"
    ManagedBy = "Terraform"
  }
}
