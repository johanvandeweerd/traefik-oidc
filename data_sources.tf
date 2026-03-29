data "aws_region" "this" {
}

data "aws_availability_zones" "this" {
}

data "aws_route53_zone" "this" {
  name = var.hosted_zone
}

data "aws_ssoadmin_instances" "this" {
}

data "aws_identitystore_group" "argocd_admin" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "ArgocdAdmin"
    }
  }
}
