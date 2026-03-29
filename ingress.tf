# Load Balancer
module "load_balancer_certificate" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "*.${local.hostname}"
  zone_id     = aws_route53_zone.this.zone_id

  validation_method = "DNS"

  wait_for_validation = true
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 10.0"

  name    = var.project_name
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  load_balancer_type         = "application"
  enable_deletion_protection = false
  preserve_host_header       = true
  xff_header_processing_mode = "append" // "preserve"

  security_group_name            = "${var.project_name}-alb"
  security_group_use_name_prefix = false
  security_group_description     = "TF: Security group used by the ALB for the ${var.project_name} cluster."
  security_group_ingress_rules = {
    http = {
      description = "TF: HTTP web traffic"
      ip_protocol = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = "0.0.0.0/0"
    }
    https = {
      description = "TF: HTTPS web traffic"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      description = "TF: all outbound traffic"
      ip_protocol = "all"
      from_port   = -1
      to_port     = -1
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_tags = {
    Name = "${var.project_name}-alb"
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "traefik-http"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.load_balancer_certificate.acm_certificate_arn
      forward = {
        target_group_key = "traefik-https"
      }
    }
  }

  target_groups = {
    traefik-http = {
      name              = "${var.project_name}-traefik-http"
      target_type       = "ip"
      protocol          = "HTTP"
      port              = 8000
      create_attachment = false
      health_check = {
        enabled  = true
        path     = "/ping"
        port     = "8080"
        protocol = "HTTP"
      }
      tags = {
        # Tag is needed to grant AWS Load Balancer Controller the necessary IAM permissions.
        # https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html#:~:text=currently%20not%20supported-,TargetGroupBinding,-Previous
        "eks:eks-cluster-name" : module.eks.cluster_name
      }
    }
    traefik-https = {
      name              = "${var.project_name}-traefik-https"
      target_type       = "ip"
      protocol          = "HTTPS"
      port              = 8443
      create_attachment = false
      health_check = {
        enabled  = true
        path     = "/ping"
        port     = "8080"
        protocol = "HTTP"
      }
      tags = {
        # Tag is needed to grant AWS Load Balancer Controller the necessary IAM permissions.
        # https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html#:~:text=currently%20not%20supported-,TargetGroupBinding,-Previous
        "eks:eks-cluster-name" : module.eks.cluster_name
      }
    }
  }
}

resource "aws_security_group_rule" "allow_alb_to_worker_nodes_on_8443" {
  security_group_id        = aws_security_group.node.id
  description              = "TF: Allow ALB to communicate with worker nodes on port 8443"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8443
  to_port                  = 8443
  source_security_group_id = module.alb.security_group_id
}

resource "aws_security_group_rule" "allow_alb_to_worker_nodes_on_8080" {
  security_group_id        = aws_security_group.node.id
  description              = "TF: Allow ALB to do Traefik health check with worker nodes on port 8080"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = module.alb.security_group_id
}

resource "aws_route53_record" "star" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "*"
  type    = "A"

  alias {
    zone_id                = module.alb.zone_id
    name                   = module.alb.dns_name
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "load_balancer" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "load-balancer"
  type    = "A"

  alias {
    zone_id                = module.alb.zone_id
    name                   = module.alb.dns_name
    evaluate_target_health = false
  }
}
