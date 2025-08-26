############################################
# Outputs
############################################

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "kubectl_auth_hint" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  value = aws_db_instance.hive.address
}

output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "iceberg_bucket" {
  value = aws_s3_bucket.iceberg.bucket
}

output "ecr_spark_repo" {
  value = aws_ecr_repository.spark.repository_url
}

output "ecr_hive_repo" {
  value = aws_ecr_repository.hive.repository_url
}

output "ecr_spark_operator_repo" {
  value = aws_ecr_repository.spark_operator.repository_url
}

output "ecr_hive_metastore_repo" {
  value = aws_ecr_repository.hive_metastore.repository_url
}

output "ecr_spark_ingest_repo" {
  value = aws_ecr_repository.spark_ingest.repository_url
}

output "ecr_spark_aggregation_repo" {
  value = aws_ecr_repository.spark_aggregation.repository_url
}

output "ecr_spark_samples_repo" {
  value = aws_ecr_repository.spark_samples.repository_url
}

output "ecr_spark_jobs_base_repo" {
  value = aws_ecr_repository.spark_jobs_base.repository_url
}

# Output the IAM role ARNs for use in Phase 2
output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "spark_apps_role_arn" {
  value = aws_iam_role.spark_apps.arn
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "clickhouse_role_arn" {
  value = aws_iam_role.clickhouse.arn
}

output "phase1_complete" {
  value = <<-EOT
    ============================================
    Phase 1 Deployment Complete! 
    ============================================
    
    EKS Cluster: ${module.eks.cluster_name}
    Region: ${var.aws_region}
    
    Next Steps:
    
    1. Configure kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
    
    2. Verify cluster access:
       kubectl get nodes
    
    3. Deploy Kubernetes resources:
       Create file 06-kubernetes.tf with all Kubernetes/Helm resources
       Then run: terraform plan && terraform apply
    
    ============================================
  EOT
}
