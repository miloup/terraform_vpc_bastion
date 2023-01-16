resource "aws_vpc" "eks" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "rafik-vpc"
  }
}

locals {
  availability_zones = [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c"
  ]
}

resource "aws_subnet" "private" {
  count             = length(var.subnet_private_cidr)
  cidr_block        = element(var.subnet_private_cidr, count.index)
  vpc_id            = aws_vpc.eks.id
  availability_zone = local.availability_zones[count.index]
  tags = {
    Name                                             = "subnet-private-${count.index}-${local.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"                = 1
    "kubernetes.io/cluster/${var.cluster_full_name}" = "shared"
  }
}

resource "aws_route_table" "private" {
  count  = length(var.subnet_private_cidr)
  vpc_id = aws_vpc.eks.id
}

resource "aws_route" "private_to_nat" {
  count                  = length(var.subnet_private_cidr)
  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.private.*.id, count.index)
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.subnet_private_cidr)
  route_table_id = element(aws_route_table.private.*.id, count.index)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
}

resource "aws_subnet" "public" {
  count             = length(var.subnet_public_cidr)
  cidr_block        = element(var.subnet_public_cidr, count.index)
  vpc_id            = aws_vpc.eks.id
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "subnet-public-${count.index}-${local.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id
}

resource "aws_route" "public_to_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.eks_igw.id
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "eks_public_rt_association" {
  count          = length(var.subnet_public_cidr)
  route_table_id = aws_route_table.public.id
  subnet_id      = element(aws_subnet.public.*.id, count.index)
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks.id
}

resource "aws_nat_gateway" "private" {
  count         = length(var.subnet_public_cidr)
  allocation_id = element(aws_eip.eks_nat_ips.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)
}

resource "aws_eip" "eks_nat_ips" {
  count = length(var.subnet_private_cidr)
  vpc   = true
}


# VPC Association
resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id     = aws_vpc.eks.id
  cidr_block = "100.64.0.0/16"
}

resource "aws_subnet" "secondary_private" {
  depends_on        = [aws_vpc_ipv4_cidr_block_association.secondary_cidr]
  count             = length(var.secondary_subnet_private_cidr)
  cidr_block        = element(var.secondary_subnet_private_cidr, count.index)
  vpc_id            = aws_vpc.eks.id
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "subnet-secondary-private-${count.index}-${local.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "secondary" {
  count          = length(var.secondary_subnet_private_cidr)
  route_table_id = element(aws_route_table.private.*.id, count.index)
  subnet_id      = element(aws_subnet.secondary_private.*.id, count.index)
}

resource "aws_vpc_endpoint" "mandatory" {
  for_each          = var.vpc_endpoints
  vpc_id            = aws_vpc.eks.id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = each.value
}
