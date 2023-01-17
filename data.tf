data "aws_caller_identity" "current" {}

data "aws_ebs_volume" "jenkins" {
  most_recent = true

  filter {
    name   = "volume-type"
    values = ["gp2"]
  }

  filter {
    name   = "tag:Name"
    values = ["rafik-jenkins"]
  }
}

data "aws_route53_zone" "main" {
  name         = "${var.route53_public_dns}."
  private_zone = false
}
