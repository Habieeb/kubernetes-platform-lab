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
