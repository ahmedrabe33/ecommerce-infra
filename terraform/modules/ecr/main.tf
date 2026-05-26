resource "aws_ecr_repository" "services" {
  for_each             = toset(var.services)
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration    { encryption_type = "AES256" }
  tags = { Name = each.value }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 20 tagged images"
        selection = { tagStatus = "tagged", tagPrefixList = ["v","sha","latest"], countType = "imageCountMoreThan", countNumber = 20 }
        action = { type = "expire" }
      }
    ]
  })
}
