variable "aws_region" {
  description = "The AWS region to deploy the resources."
  type        = string
}

variable "project_name" {
  description = "Name to use for the VPC, EKS cluster, etc and to use as prefix to name resources."
  type        = string
}

variable "kubernetes_version" {
  description = "The version of Kubernetes to use."
  type        = string
}

variable "hosted_zone" {
  description = "The hosted zone under which the project name is used as a subdomain for this project."
  type        = string
}

variable "github_repository" {
  description = "The url to the Github repository to use for Argocd applications."
  type        = string
}

variable "github_branch" {
  description = "The name of the Github branch to use for Argocd applications."
  type        = string
}

