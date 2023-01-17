output "bastion_role_arn" {
  value = aws_iam_role.bastion.arn
}

output "alb_endpoint" {
  value = aws_lb.jenkins.dns_name
}

output "vpc_id" {
  value = aws_vpc.eks.id
}

output "public_subnets_id" {
  value = aws_subnet.public.*.id
}

output "private_subnets_id" {
  value = aws_subnet.private.*.id
}

output "private_secondary_subnets_id" {
  value = aws_subnet.secondary_private.*.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}
