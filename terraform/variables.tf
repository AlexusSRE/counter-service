variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "alex-counter-service"
}

variable "cluster_name" {
  type    = string
  default = "alex-counter-service-cluster"
}

variable "github_org" {
  type    = string
  default = "AlexusSRE"
}

variable "github_repo" {
  type    = string
  default = "counter-service"
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
  validation {
    condition     = length(var.db_password) >= 12
    error_message = "db_password must be at least 12 characters."
  }
}

variable "enable_rds_backups" {
  type    = bool
  default = true
}

variable "tags" {
  type = map(string)
  default = {
    Project = "counter-service"
    Owner   = "AlexusSRE"
    Env     = "dev"
  }
}
