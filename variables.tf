variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "aws region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.100.0.0/16"
  description = "main VPC cidr"
}

variable "subnet_public_cidr" {
  type        = list(string)
  default     = ["10.100.0.0/24", "10.100.2.0/24", "10.100.4.0/24"]
  description = "public subnet CIDRS"
}

variable "subnet_private_cidr" {
  type        = list(string)
  default     = ["10.100.1.0/24", "10.100.3.0/24", "10.100.5.0/24"]
  description = "private subnet CIDRS"
}

variable "secondary_vpc_cidr" {
  type        = string
  default     = "100.64.0.0/16"
  description = "secondary VPC cidr"
}

variable "secondary_subnet_private_cidr" {
  type        = list(string)
  default     = ["100.64.0.0/18", "100.64.64.0/18", "100.64.128.0/18"]
  description = "private subnet CIDRS"
}

variable "vpc_endpoints" {
  type = map(string)
  default = {
    "dynamodb"    = "Gateway",
    "ec2messages" = "Interface",
    "eks"         = "Interface",
    "s3"          = "Gateway",
    "ssm"         = "Interface",
    "ssmmessages" = "Interface",
  }
}

variable "route53_public_dns" {
  default = "k8s.dev.aws.gotocloud.io"
}
