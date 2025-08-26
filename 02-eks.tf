############################################
# EKS Cluster
############################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name                   = "${local.name_prefix}-eks"
  cluster_version                = var.eks_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  enable_irsa = true

  eks_managed_node_groups = {
    ng_spot = {
      name                  = "ng-spot"
      instance_types        = var.node_instance_types
      capacity_type         = "SPOT"
      desired_size          = var.node_size
      min_size              = var.node_size
      max_size              = max(var.node_size, 10)
      subnet_ids            = module.vpc.public_subnets
      ami_type              = "AL2023_x86_64_STANDARD"
      disk_size             = 80
      create_security_group = true
      labels = {
        role     = "executors"
        capacity = "spot"
      }
      tags = local.tags
    }
    ng_sys = {
      name                  = "ng-sys-ondemand"
      instance_types        = var.sys_node_instance_types
      capacity_type         = "ON_DEMAND"
      desired_size          = var.sys_node_size
      min_size              = var.sys_node_size
      max_size              = var.sys_node_size
      subnet_ids            = module.vpc.public_subnets
      ami_type              = "AL2023_x86_64_STANDARD"
      disk_size             = 30
      create_security_group = true
      labels = {
        role     = "system"
        capacity = "on-demand"
      }
      tags = local.tags
    }
  }

  tags = local.tags
}

########################
# ECR repositories
########################
resource "aws_ecr_repository" "spark" {
  name                 = "${local.name_prefix}/spark"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "hive" {
  name                 = "${local.name_prefix}/hive"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "spark_operator" {
  name                 = "${local.name_prefix}/spark-operator"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# Additional ECR repositories for production workloads
resource "aws_ecr_repository" "hive_metastore" {
  name                 = "${local.name_prefix}/hive-metastore"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "spark_ingest" {
  name                 = "${local.name_prefix}/spark-ingest"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "spark_aggregation" {
  name                 = "${local.name_prefix}/spark-aggregation"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "spark_samples" {
  name                 = "${local.name_prefix}/spark-samples"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_repository" "spark_jobs_base" {
  name                 = "${local.name_prefix}/spark-jobs-base"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}
