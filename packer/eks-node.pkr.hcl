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

source "amazon-ebs" "eks_node" {
  region        = var.aws_region
  instance_type = "t3.small"
  ssh_username  = "ec2-user"

  source_ami_filter {
    filters = {
      name                = "amazon-eks-node-${var.kubernetes_version}-v*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }

    owners      = ["602401143452"]
    most_recent = true
  }

  ami_name = "platform-lab-eks-${var.kubernetes_version}-{{timestamp}}"

  tags = {
    Name      = "platform-lab-eks-node"
    Project   = "kubernetes-platform-lab"
    ManagedBy = "Packer"
  }
}

build {
  sources = ["source.amazon-ebs.eks_node"]

  provisioner "shell" {
    inline = [
      "echo 'Platform Lab custom EKS node AMI'",
      "sudo mkdir -p /opt/platform-lab",
      "echo 'Built by Packer' | sudo tee /opt/platform-lab/README"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
