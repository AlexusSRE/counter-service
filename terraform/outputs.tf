output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "backend_ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "adot_irsa_role_arn" {
  value = aws_iam_role.adot_collector.arn
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend.domain_name
}
