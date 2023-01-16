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

  bastion_access = templatefile("${path.root}/manifests/eks-access-bastion.yaml", {
    bastion_role_arn = aws_iam_role.bastion.arn,
    worker_role_arn  = aws_iam_role.workers.arn
  })
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

resource "aws_security_group_rule" "bastion_access_to_api_server" {
  description              = "Allow cluster control plane to receive communication from the bastion server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster_sg.id
  source_security_group_id = aws_security_group.bastion.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_instance" "bastion" {
  ami                    = "ami-0fe0b2cf0e1f25c8a" # amazon-linux-2
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.private[0].id
  user_data_base64       = base64encode(local.bastion_user_data)
  iam_instance_profile   = aws_iam_instance_profile.bastion.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "rafik-jump-box"
  }

  depends_on = [aws_route_table_association.private]
}

resource "aws_security_group" "alb" {
  name        = "alb-rafik"
  description = "Security group for the ALB"
  vpc_id      = aws_vpc.eks.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["207.45.249.131/32"]
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

resource "aws_lb_listener" "jenkins" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
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
