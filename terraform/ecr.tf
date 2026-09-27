resource "aws_ecr_repository" "app" {
  name                 = "platform-lab-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true
}
