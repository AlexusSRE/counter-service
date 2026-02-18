output "region" {
  value = var.region
}

output "cluster_name" {
  value = data.aws_eks_cluster.this.name
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

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}
