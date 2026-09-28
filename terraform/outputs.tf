output "ecr_repository_url" {
  description = "ECR repository URL used by Jenkins"
  value       = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region used by the lab"
  value       = var.aws_region
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name used by EC2 nodes provisioned by Karpenter"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN used by EC2 nodes provisioned by Karpenter"
  value       = module.karpenter.node_iam_role_arn
}
