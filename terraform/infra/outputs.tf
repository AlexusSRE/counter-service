output "region" {
  value = var.region
}

output "cluster_name" {
  value = data.aws_eks_cluster.platform.name
}

output "cluster_endpoint" {
  value = data.aws_eks_cluster.platform.endpoint
}

output "cluster_certificate_authority_data" {
  value     = data.aws_eks_cluster.platform.certificate_authority[0].data
  sensitive = true
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer" {
  value = local.oidc_issuer
}

output "vpc_id" {
  value = data.aws_vpc.platform.id
}

output "public_subnet_ids" {
  value       = values(aws_subnet.public)[*].id
  description = "Public subnet IDs where internet-facing ALBs should be created (for verification)."
}

output "node_group_role_arn" {
  value = aws_iam_role.node_group.arn
}

output "backend_ecr_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}
