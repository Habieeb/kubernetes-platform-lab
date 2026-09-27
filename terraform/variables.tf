variable "aws_region" {
  description = "AWS region used for the platform lab"
  type        = string
  default     = "eu-west-1"
}

variable "node_ami_id" {
  description = "Custom EKS worker-node AMI built by Packer"
  type        = string
  default     = null
}
