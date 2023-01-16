## Description
This repo creates the following AWS resources using Terraform:
- 1 VPC.
- 3 public subnets (behind and Internet Gateway).
- 3 Private subnets (behind NAT Gateways).
- 1 VPC associations (extension) + 3 private subnets.
- 1 bastion server deployed in a private subnet that hosts a Jenkins server.
- The bastion server is behind a public ALB that allows ingress traffic from the SocGen IP only.