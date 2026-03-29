module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.project_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access = true
  endpoint_public_access  = true

  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled = true
  }

  iam_role_name            = "${var.project_name}-eks"
  iam_role_use_name_prefix = false
  iam_role_description     = "TF: IAM role used by the ${var.project_name} cluster control plane."

  node_iam_role_name            = "${var.project_name}-eks-node"
  node_iam_role_use_name_prefix = false
  node_iam_role_description     = "TF: IAM role used by the ${var.project_name} cluster worker nodes."
  node_iam_role_additional_policies = {
    AmazonEKS_CNI_Policy = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  }

  create_security_group      = false
  create_node_security_group = false

  cloudwatch_log_group_retention_in_days = 7
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_policy_name            = "${var.project_name}-encryption"
  encryption_policy_use_name_prefix = false
  encryption_policy_description     = "TF: IAM policy used by the ${var.project_name} cluster for encryption."
}

# https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html#auto-node-access-entry
resource "aws_eks_access_entry" "node" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks.node_iam_role_arn
  type          = "EC2"
}

resource "aws_eks_access_policy_association" "node" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.node.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_security_group" "node" {
  vpc_id      = module.vpc.vpc_id
  name        = "${var.project_name}-eks-node"
  description = "TF: Security group used by the ${var.project_name} cluster worker nodes."
  tags = {
    Name = "${var.project_name}-eks-node"
  }
}

resource "kubectl_manifest" "node_class" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      ephemeralStorage = {
        size = "50Gi"
      }
      networkPolicy          = "DefaultAllow"
      networkPolicyEventLogs = "Disabled"
      role                   = module.eks.node_iam_role_name
      subnetSelectorTerms = [
        { tags = { Name = "${var.project_name}-private-*" } },
      ]
      securityGroupSelectorTerms = [
        { tags = { Name = "eks-cluster-sg-${var.project_name}-*" } },
        { tags = { Name = aws_security_group.node.name } },
      ]
    }
  })
}

resource "kubectl_manifest" "node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general-purpose"
    }
    spec = {
      disruption = {
        budgets = [
          { nodes = "10%" }
        ]
        consolidateAfter    = "30s"
        consolidationPolicy = "WhenEmptyOrUnderutilized"
      }
      template = {
        spec = {
          expireAfter = "48h"
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand", "spot"]
            },
            {
              key      = "eks.amazonaws.com/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "eks.amazonaws.com/instance-generation"
              operator = "Gt"
              values   = ["4"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "eks.amazonaws.com/instance-memory"
              operator = "Gt"
              values   = ["2048"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            },
          ]
          terminationGracePeriod = "24h0m0s"
        }
      }
    }
  })
}
