# Production Workloads Configuration
# This file contains additional ECR repositories and variables for production workloads
# that were identified in the current cluster but may be deployed separately

#################
# Variables for Production Images
#################

# Variable for jobs-hive-iceberg image (observed in production)
variable "jobs_hive_iceberg_image" {
  type        = string
  default     = "503233514096.dkr.ecr.us-east-1.amazonaws.com/jobs-hive-iceberg:latest"
  description = "Container image for Hive-Iceberg integration jobs"
}

# Variable for log ingestion ECR repository  
variable "log_ingest_spark_image" {
  type        = string
  default     = "503233514096.dkr.ecr.us-east-1.amazonaws.com/log-ingest-spark:v12"
  description = "Container image for log ingestion Spark jobs"
}

#################
# Additional ECR Repositories for Future Use
#################

# ECR repository for jobs-hive-iceberg (if needed as separate repo)
resource "aws_ecr_repository" "jobs_hive_iceberg" {
  count                = 0 # Set to 1 when needed
  name                 = "${local.name_prefix}/jobs-hive-iceberg"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# ECR repository for log-ingest-spark (if needed as separate repo)
resource "aws_ecr_repository" "log_ingest_spark" {
  count                = 0 # Set to 1 when needed
  name                 = "${local.name_prefix}/log-ingest-spark"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

#################
# Documentation of Current Production Workloads
#################

# Note: The following workloads were observed running in production:
#
# 1. logs-ingestion-prod-driver
#    - Image: 503233514096.dkr.ecr.us-east-1.amazonaws.com/jobs-hive-iceberg:latest
#    - Class: org.apache.spark.deploy.PythonRunner
#    - Main: local:///opt/jobs/simple_iceberg_ingest.py
#    - Resources: 2 CPU, 2867Mi memory
#    - Service Account: spark-apps
#    - Status: Failed (due to resource constraints)
#
# These applications should be recreated as SparkApplication manifests
# or scheduled jobs after the fresh deployment is complete.

#################
# Production Spark Application Templates
#################

# Commented out production Spark applications - uncomment and modify as needed
# after fresh cluster deployment

/*
# Production Log Ingestion Job
resource "kubernetes_manifest" "production_log_ingestion" {
  count = 0 # Enable when ready for production deployment
  
  manifest = {
    apiVersion = "sparkoperator.k8s.io/v1beta2"
    kind       = "SparkApplication"
    metadata = {
      name      = "logs-ingestion-prod"
      namespace = var.spark_namespace
    }
    spec = {
      type                = "Python"
      mode                = "cluster"
      image               = var.jobs_hive_iceberg_image
      imagePullPolicy     = "Always"
      mainApplicationFile = "local:///opt/jobs/simple_iceberg_ingest.py"
      sparkVersion        = "3.5.3"
      restartPolicy = {
        type = "Never"
      }
      
      driver = {
        cores         = 1
        memory        = "1g"
        serviceAccount = "spark-apps"
      }
      
      executor = {
        cores     = 1
        instances = 2
        memory    = "2g"
        serviceAccount = "spark-apps"
      }
    }
  }
  
  depends_on = [
    kubernetes_service_account.spark_apps,
    kubernetes_service.hive_metastore
  ]
}
*/
