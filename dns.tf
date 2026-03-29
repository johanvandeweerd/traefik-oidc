resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.project_name
  type    = "NS"
  ttl     = 172800
  records = aws_route53_zone.this.name_servers
}

resource "aws_route53_zone" "this" {
  name = "${var.project_name}.${var.hosted_zone}"
}
