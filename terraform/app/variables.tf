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
  default = "alex-counter-service"
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

variable "tags" {
  type = map(string)
  default = {
    Project = "alex-counter-service"
    Owner   = "AlexusSRE"
    Env     = "dev"
  }
}
