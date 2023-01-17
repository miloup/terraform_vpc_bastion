resource "aws_iam_role" "bastion" {
  name = "rafik-bastion"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF

  inline_policy {
    name   = "ssm_eks"
    policy = <<-POLICY
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "eks:DescribeCluster",
            "eks:AccessKubernetesApi",
            "s3:*"
          ],
          "Resource": "*"
        }
      ]
    }
    POLICY
  }
}

resource "aws_iam_role_policy_attachment" "bastion_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_instance_profile" "bastion" {
  name = "rafik-bastion"
  role = aws_iam_role.bastion.name
}

locals {
  bastion_user_data = <<-EOT
    #!/bin/bash
    set -ex

    yum update -y

    # Install necessary binaries
    curl -LO https://dl.k8s.io/release/v1.23.15/bin/linux/amd64/kubectl && \
        chmod +x kubectl &&\
        mv kubectl /usr/bin/kubectl
    wget https://get.helm.sh/helm-v3.8.2-linux-amd64.tar.gz && \
        tar -zxf helm-v3.8.2-linux-amd64.tar.gz && \
        chmod +x linux-amd64/helm &&\
        mv linux-amd64/helm /usr/bin/helm
    
    # Install Jenkins
    wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
    yum upgrade -y
    amazon-linux-extras install java-openjdk11
    yum install -y jenkins
    systemctl daemon-reload
    systemctl enable jenkins
    systemctl start jenkins

  EOT
}

resource "aws_security_group" "bastion" {
  name        = "bastion-rafik"
  description = "Security group for the bastion server"
  vpc_id      = aws_vpc.eks.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-rafik-sg"
  }
}

resource "aws_security_group_rule" "alb_to_bastion_8080" {
  description              = "Allow ALB to communicate with jenkins on port 8080"
  from_port                = 0
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion.id
  source_security_group_id = aws_security_group.alb.id
  to_port                  = 8080
  type                     = "ingress"
}

resource "aws_instance" "bastion" {
  ami                    = "ami-0fe0b2cf0e1f25c8a" # amazon-linux-2
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private[0].id
  user_data_base64       = base64encode(local.bastion_user_data)
  iam_instance_profile   = aws_iam_instance_profile.bastion.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "rafik-jump-box"
  }

  depends_on = [aws_route.private_to_nat]
}

# resource "aws_volume_attachment" "jenkins" {
#   device_name = "/dev/sdf"
#   # device_name = "/dev/nvme0n1p1"
#   volume_id   = data.aws_ebs_volume.jenkins.id
#   instance_id = aws_instance.bastion.id
# }

resource "aws_security_group" "alb" {
  name        = "alb-rafik"
  description = "Security group for the ALB"
  vpc_id      = aws_vpc.eks.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-rafik-sg"
  }
}

resource "aws_lb" "jenkins" {
  name               = "rafik-jenkins"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false
}

resource "aws_lb_listener" "jenkins_80" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"

    }
    # target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener" "jenkins_443" {
  certificate_arn   = aws_acm_certificate.jenkins.arn
  load_balancer_arn = aws_lb.jenkins.arn
  port              = "443"
  protocol          = "HTTPS"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "This endpoint is not authorized or does not exist."
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "jenkins" {
  listener_arn = aws_lb_listener.jenkins_443.arn

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    host_header {
      values = [aws_route53_record.jenkins.name]
    }
  }
}

resource "aws_lb_target_group" "jenkins" {
  name     = "jenkins-lb-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.eks.id

  health_check {
    matcher = "200-403"
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.bastion.id
  port             = 8080
}

resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "jenkins.${var.route53_public_dns}"
  type    = "A"
  alias {
    name                   = aws_lb.jenkins.dns_name
    zone_id                = aws_lb.jenkins.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cert_validation" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = tolist(aws_acm_certificate.jenkins.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.jenkins.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.jenkins.domain_validation_options)[0].resource_record_type
  ttl             = 60
}

resource "aws_acm_certificate" "jenkins" {
  domain_name       = "jenkins.${var.route53_public_dns}"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "jenkins" {
  certificate_arn         = aws_acm_certificate.jenkins.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}
