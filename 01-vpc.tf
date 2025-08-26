############################################
# VPC and Networking
############################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.7"

  name = "${local.name_prefix}-vpc"
  cidr = "10.42.0.0/16"

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway             = var.enable_nat_gateway
  single_nat_gateway             = true
  enable_dns_hostnames           = true
  enable_dns_support             = true
  map_public_ip_on_launch        = true

  tags = local.tags
}

############################################
# VPC Endpoints (avoid NAT per‑GB charges)
############################################
resource "aws_vpc_endpoint" "s3" {
  count             = var.create_vpc_endpoints ? 1 : 0
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  tags              = merge(local.tags, { Purpose = "s3-gateway" })
}

resource "aws_security_group" "vpce_https" {
  count = var.create_vpc_endpoints ? 1 : 0

  name   = "${local.name_prefix}-vpce-https"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

locals {
  interface_services = var.create_vpc_endpoints ? [
    "com.amazonaws.${var.aws_region}.secretsmanager",
    "com.amazonaws.${var.aws_region}.ecr.api",
    "com.amazonaws.${var.aws_region}.ecr.dkr",
    "com.amazonaws.${var.aws_region}.sts"
  ] : []
}

resource "aws_vpc_endpoint" "interfaces" {
  for_each            = toset(local.interface_services)
  vpc_id              = module.vpc.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.multi_az ? module.vpc.private_subnets : [module.vpc.private_subnets[0]]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_https[0].id]
  tags                = merge(local.tags, { Purpose = "interface-endpoint" })
}
