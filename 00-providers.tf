############################################
# Terraform Providers and Variables
############################################

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}


#################
# Variables
#################
variable "project_name" {
  type    = string
  default = "data-platform"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_version" {
  type    = string
  default = "1.33"
}

# Placement & VPC cost knobs
variable "preferred_az" {
  type    = string
  default = "us-east-1a"
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

variable "create_vpc_endpoints" {
  type    = bool
  default = true
}

# EKS nodes
variable "node_instance_types" {
  type    = list(string)
  default = ["m5.xlarge", "m5a.xlarge", "c5.xlarge"]
}

variable "node_size" {
  type    = number
  default = 1
}

# On-demand system NG for system/control helpers - scaled up for Phase 2
variable "sys_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "sys_node_size" {
  type    = number
  default = 2
}

# Spark Operator & optional example app
variable "spark_namespace" {
  type    = string
  default = "spark"
}

variable "deploy_example_spark_app" {
  type    = bool
  default = false
}

variable "deploy_spark_jobs" {
  type    = bool
  default = false
  description = "Deploy the log ingestion and aggregation Spark jobs"
}

variable "spark_image" {
  type    = string
  default = "apache/spark:3.5.1"
}

variable "spark_executor_instances" {
  type    = number
  default = 3
}

# Spark + Iceberg jars (for example app)
variable "spark_jars_packages" {
  type    = string
  default = "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.2,org.apache.hadoop:hadoop-aws:3.3.6,com.amazonaws:aws-java-sdk-bundle:1.12.772"
}

# Spark Operator image (override to ECR after mirror)
variable "spark_operator_image" {
  type    = string
  default = "gcr.io/spark-operator/spark-operator"
}

variable "spark_operator_image_tag" {
  type    = string
  default = "v1beta2-1.3.10-3.5"
}

# HMS / RDS
variable "hive_namespace" {
  type    = string
  default = "hive"
}

variable "db_engine_version" {
  type    = string
  default = "8.0.39"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "db_name" {
  type    = string
  default = "hivemetastore"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "hive_metastore_image" {
  type    = string
  default = "503233514096.dkr.ecr.us-east-1.amazonaws.com/data-platform/hive:3.1.3-pg42-s3a"
}

variable "hive_metastore_replicas" {
  type    = number
  default = 1
}

# ESO namespace
variable "eso_namespace" {
  type    = string
  default = "external-secrets"
}

# Buckets & prefix policy knobs
variable "s3_raw_bucket_name" {
  type    = string
  default = null
}

variable "s3_iceberg_bucket_name" {
  type    = string
  default = null
}

# Prefix scopes for IAM (fine-grained)
variable "raw_ro_prefixes" {
  type    = list(string)
  default = ["ingestion/*"]
}

variable "raw_rw_prefixes" {
  type    = list(string)
  default = ["spark-logs/*"]
  description = "Prefixes in raw bucket that need read-write access"
}

variable "iceberg_rw_prefixes" {
  type    = list(string)
  default = ["warehouse/*"]
}

# ClickHouse
variable "clickhouse_namespace" {
  type    = string
  default = "clickhouse"
}

#################
# Provider Configuration
#################
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

#################
# Locals & Data Sources
#################
locals {
  name_prefix = var.project_name
  tags = {
    Project = var.project_name
    Stack   = "eks-spark-hive"
    Managed = "terraform"
  }
}

data "aws_caller_identity" "me" {}

data "aws_availability_zones" "azs" {}

locals {
  secondary_az    = tolist([for az in data.aws_availability_zones.azs.names : az if az != var.preferred_az])[0]
  azs             = var.multi_az ? slice(data.aws_availability_zones.azs.names, 0, 3) : [var.preferred_az, local.secondary_az]
  private_subnets = var.multi_az ? ["10.42.1.0/24", "10.42.2.0/24", "10.42.3.0/24"] : ["10.42.1.0/24", "10.42.2.0/24"]
  public_subnets  = var.multi_az ? ["10.42.101.0/24", "10.42.102.0/24", "10.42.103.0/24"] : ["10.42.101.0/24", "10.42.102.0/24"]
}
