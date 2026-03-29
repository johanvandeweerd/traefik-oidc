resource "aws_eks_capability" "argocd" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "argocd"
  type                      = "ARGOCD"
  role_arn                  = aws_eks_access_policy_association.argocd_cluster.principal_arn
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      aws_idc {
        idc_instance_arn = data.aws_ssoadmin_instances.this.arns[0]
        idc_region       = data.aws_region.this.id
      }
      namespace = "argocd"
      rbac_role_mapping {
        role = "ADMIN"
        identity {
          type = "SSO_GROUP"
          id   = data.aws_identitystore_group.argocd_admin.id
        }
      }
    }
  }
}

# We need to manually create the access entry and policy association for Argocd to work properly. Otherwise the creation of the capability fails with the following error. Not sure why this is 🤷‍♂️
# InvalidParameterException: The trust policy for the provided role is invalid. The policy must include sts:AssumeRole and sts:TagSession actions granting access to the AWS service capabilities.eks.amazonaws.com
resource "aws_eks_access_entry" "argocd" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.argocd_iam_role.arn
}

resource "aws_eks_access_policy_association" "argocd_cluster" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.argocd.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSArgoCDClusterPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_policy_association" "argocd_argocd" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.argocd.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSArgoCDPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["argocd"]
  }
}

# I'm not happy with this but I couldn't find another way to give ArgoCD the necessary permissions to create all the resources it needs.
resource "aws_eks_access_policy_association" "argocd_cluster_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.argocd.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

module "argocd_iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name            = "${var.project_name}-argocd"
  use_name_prefix = false
  description     = "TF: IAM role used by Argocd EKS capability."

  trust_policy_permissions = {
    EksCapabilities = {
      effect = "Allow"
      actions = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      principals = [{
        type        = "Service"
        identifiers = ["capabilities.eks.amazonaws.com"]
      }]
    }
  }
}

resource "kubectl_manifest" "argocd_secret_local_cluster" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      labels = {
        "argocd.argoproj.io/secret-type" = "cluster"
      }
      name      = "local-cluster"
      namespace = "argocd"
    }
    stringData = {
      name    = "local-cluster"
      server  = module.eks.cluster_arn
      project = "default"
    }
  })

  depends_on = [aws_eks_capability.argocd]
}

locals {
  apps = {
    cert-manager = {
      namespace = "cert-manager"
      values = {
        email        = var.email
        loadBalancer = aws_route53_record.load_balancer.fqdn
      }
    }
    traefik = {
      namespace = "traefik"
      values = {
        targetGroupArn = {
          http  = module.alb.target_groups["traefik-http"].arn
          https = module.alb.target_groups["traefik-https"].arn
        }
      }
    }
  }
}

resource "kubectl_manifest" "argocd_applications" {
  for_each = local.apps

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = each.key
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repository
        targetRevision = var.github_branch
        path           = "applications/${each.key}"
        helm = {
          valuesObject = try(each.value.values, {})
        }
      }
      destination = {
        server    = module.eks.cluster_arn
        namespace = try(each.value.namespace, "default")
      }
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=true"
        ]
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [aws_eks_capability.argocd]
}
