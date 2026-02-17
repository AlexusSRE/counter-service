variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "counter-service"
}

variable "cluster_name" {
  type    = string
  default = "<CLUSTER_NAME>"
}

variable "github_org" {
  type    = string
  default = "<GITHUB_ORG>"
}

variable "github_repo" {
  type    = string
  default = "<REPO_NAME>"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "db_name" {
  type    = string
  default = "counter"
}

variable "db_username" {
  type    = string
  default = "counter"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "enable_rds_backups" {
  type    = bool
  default = true
}

variable "frontend_lb_dns_name" {
  type        = string
  description = "Frontend LoadBalancer DNS name for CloudFront origin"
  default     = ""
}
