resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"

  description = "Service-linked role for EC2 Spot Instances used by Karpenter"
}
