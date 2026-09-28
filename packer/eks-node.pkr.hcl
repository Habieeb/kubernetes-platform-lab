packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "git_commit" {
  type        = string
  description = "Git commit associated with this AMI build"
}

source "amazon-ebs" "eks_node" {
  region        = var.aws_region
  instance_type = "t3.small"
  ssh_username  = "ec2-user"

  source_ami_filter {
    filters = {
      name                = "amazon-eks-node-al2023-x86_64-standard-${var.kubernetes_version}-v*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture        = "x86_64"
    }

    owners      = ["602401143452"]
    most_recent = true
  }

  ami_name = "platform-lab-eks-al2023-${var.kubernetes_version}-{{timestamp}}"

  tags = {
    Name              = "platform-lab-eks-node"
    Project           = "kubernetes-platform-lab"
    ManagedBy         = "Packer"
    KubernetesVersion = var.kubernetes_version
    BaseOS            = "Amazon Linux 2023"
    GitCommit         = var.git_commit
  }
}

build {
  sources = ["source.amazon-ebs.eks_node"]

  provisioner "shell" {
    inline = [
      "echo 'Platform Lab custom EKS node AMI'",
      "sudo mkdir -p /opt/platform-lab",
      "echo 'Built by Packer from the AWS EKS-optimized AL2023 base image' | sudo tee /opt/platform-lab/README"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
