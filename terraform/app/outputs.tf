output "terraform_ci_role_arn" {
  value       = aws_iam_role.terraform_ci.arn
  description = "Use this ARN in terraform-infra.yml and terraform-app.yml"
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

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

