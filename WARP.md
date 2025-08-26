# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Project overview
- This repo provisions an AWS data infra stack with Terraform: VPC + EKS, S3 (raw/iceberg), RDS (Postgres) for Hive Metastore, ECR repos, and IAM roles for IRSA. It also includes helper scripts for mirroring container images to ECR and port-forwarding ClickHouse.
- Terraform required_version: >= 1.13.0. Primary entry files: 00-providers.tf, 01-vpc.tf, 02-eks.tf, 03-rds.tf, 04-s3.tf, 05-iam.tf, 99-outputs.tf.

Prerequisites
- Tools: terraform, awscli, kubectl, docker, jq (jq and docker are required for image mirroring).
- AWS environment: set AWS credentials in your shell (e.g., via AWS_PROFILE or env vars). Region and project defaults exist but can be overridden.

Core environment variables
- AWS_REGION: defaults to us-east-1 (in Makefile), scripts default to us-east-2 if not set explicitly.
- PROJECT: defaults to data-platform.

Common commands
- Initialize Terraform in this repo
  make init

- Plan/apply/destroy
  make plan
  make apply
  make destroy

- Configure local kubeconfig for the created EKS cluster
  make kubeconfig

- Mirror baseline images to ECR (spark, hive, spark-operator)
  # Docker and AWS credentials required
  # Optional overrides: --spark, --hive, --spark-operator
  make mirror-ecr
  # Under the hood: ./scripts/mirror_to_ecr.sh --spark apache/spark:3.5.1 --hive apache/hive:3.1.3 --spark-operator gcr.io/spark-operator/spark-operator:v1beta2-1.3.10-3.5

- Generate terraform.tfvars from existing ECR repos (sets spark_image, hive_metastore_image, spark_operator_image[_tag])
  make tfvars-from-ecr

- Port-forward services
  # ClickHouse HTTP 8123 and native 9000 (namespace defaults to clickhouse)
  make ch-port
  # Hive Metastore Thrift 9083 (namespace hive)
  make hms-port

Notes on outputs and next steps
- After apply, 99-outputs.tf prints:
  - eks_cluster_name and a kubectl_auth_hint for kubeconfig configuration
  - rds_endpoint, raw_bucket, iceberg_bucket
  - ECR repo URLs for spark, hive, spark-operator
  - IAM role ARNs for: external-secrets, spark-apps, cluster-autoscaler, clickhouse
  - A Phase 1 completion message recommending you add Kubernetes and Helm resources in a file named 06-kubernetes.tf and then plan/apply again.

High-level architecture
- Providers and variables (00-providers.tf)
  - Pins aws (~> 5.50), kubernetes (~> 2.33), helm (~> 2.13), random (~> 3.6).
  - Key variables: project_name (default data-platform), aws_region (default us-east-1), eks_version (default 1.33), multi_az (default false), enable_nat_gateway (default false), create_vpc_endpoints (default true). Node group sizing controlled by node_size and sys_node_size.
  - Spark-related variables (spark_namespace, deploy_example_spark_app, spark_image, spark_jars_packages, spark_operator_image/tag, spark_executor_instances) and HMS variables (db_*), plus bucket names and ClickHouse namespace.

- Networking (01-vpc.tf)
  - Uses terraform-aws-modules/vpc to create a VPC with public/private subnets. NAT gateway optional. DNS enabled.
  - S3 Gateway VPC endpoint and Interface endpoints (Secrets Manager, ECR API/DKR, STS) are created when create_vpc_endpoints is true to minimize NAT data costs.

- EKS and ECR (02-eks.tf)
  - EKS cluster via terraform-aws-modules/eks with addons (coredns, kube-proxy, vpc-cni, ebs-csi). IRSA enabled.
  - Two managed node groups: a spot executor pool (label role=executors) sized by node_size; and an on-demand system pool (label role=system) sized by sys_node_size.
  - ECR repositories created for spark, hive, and spark-operator images.

- RDS for Hive Metastore (03-rds.tf)
  - Postgres instance, password generated via random_password. Security group allows ingress from EKS node SG on 5432. Multi-AZ optional.
  - Subnet group across private subnets. Endpoint output is consumed by Secrets Manager entry below.

- S3 buckets (04-s3.tf)
  - raw and iceberg buckets (names can be provided or generated with random_id). Versioning and AES256 SSE enabled.
  - Public access blocked. Bucket policies deny non-TLS access. Lifecycle rules: raw transitions to STANDARD_IA at 30 days and expires noncurrent versions; iceberg expires noncurrent versions.

- IAM and IRSA (05-iam.tf)
  - Stores HMS connection details in AWS Secrets Manager (username, password, dbname, host, port, jdbc_url).
  - IRSA roles:
    - External Secrets: service account system:serviceaccount:external-secrets:external-secrets.
    - Spark Apps: system:serviceaccount:${spark_namespace}:spark-apps. Grants S3 list on specified prefixes, RO on raw prefixes, and RW on iceberg prefixes as defined by raw_ro_prefixes and iceberg_rw_prefixes.
    - Cluster Autoscaler: system:serviceaccount:kube-system:cluster-autoscaler with autoscaling/EC2/EKS describe and scaling permissions.
    - ClickHouse: system:serviceaccount:${clickhouse_namespace}:clickhouse with RO on raw and iceberg prefixes.

- Outputs (99-outputs.tf)
  - Emits cluster name, bucket names, endpoints, ECR repos, IRSA role ARNs, and explicit next-step guidance to add Kubernetes/Helm resources in 06-kubernetes.tf.

Scripts
- scripts/mirror_to_ecr.sh
  - Mirrors upstream images to your account’s ECR under ${PROJECT}/spark, ${PROJECT}/hive, ${PROJECT}/spark-operator, tagging with the source image tag. Requires docker login via aws ecr get-login-password.

- scripts/generate_tfvars_from_ecr.sh
  - Inspects existing ECR repos and writes terraform.tfvars to override spark_image/hive_metastore_image and spark-operator image/tag.

- scripts/ch_port_forward.sh
  - Port-forwards a ClickHouse pod (by label app.kubernetes.io/name=clickhouse) on ports 8123 and 9000 in the clickhouse namespace by default.

- scripts/clickhouse_iceberg_example.sql
  - Example query using ClickHouse’s iceberg table function to read Parquet Iceberg tables from the S3 warehouse path.

Conventions and phases
- Phase 1 is the cloud infra (VPC, EKS, S3, ECR, RDS, IAM). That’s what the current Terraform covers.
- Phase 2 is Kubernetes/Helm resources (operators, charts, apps). Add those to a new 06-kubernetes.tf and apply.

